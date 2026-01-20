# frozen_string_literal: true

# Service class for inventory operations.
# Encapsulates business logic and provides a clean interface for stock management.
# Based on patterns from RailsEventStore/ecommerce domain services.
#
class InventoryService
  class << self
    # Adjust stock level (positive or negative)
    def adjust_stock(inventory_item, quantity:, reason: nil, reference_type: nil, reference_id: nil, metadata: {})
      ActiveRecord::Base.transaction do
        inventory_item.lock!

        quantity_before = inventory_item.quantity_on_hand
        new_quantity = quantity_before + quantity

        unless inventory_item.backorderable? || new_quantity >= inventory_item.quantity_reserved
          raise InventoryItem::InsufficientStockError,
                "Cannot reduce stock below reserved quantity (reserved: #{inventory_item.quantity_reserved})"
        end

        inventory_item.update!(quantity_on_hand: new_quantity)

        movement = inventory_item.stock_movements.create!(
          movement_type: "adjustment",
          quantity: quantity,
          quantity_before: quantity_before,
          quantity_after: new_quantity,
          reason: reason || (quantity.positive? ? "Stock increased" : "Stock decreased"),
          reference_type: reference_type,
          reference_id: reference_id,
          metadata: metadata
        )

        publish_event(:stock_adjusted, inventory_item, movement)

        { item: inventory_item, movement: movement }
      end
    end

    # Receive new stock
    def receive_stock(inventory_item, quantity:, reason: nil, reference_type: nil, reference_id: nil, metadata: {})
      raise ArgumentError, "Quantity must be positive" if quantity <= 0

      ActiveRecord::Base.transaction do
        inventory_item.lock!

        quantity_before = inventory_item.quantity_on_hand
        new_quantity = quantity_before + quantity

        inventory_item.update!(quantity_on_hand: new_quantity)

        movement = inventory_item.stock_movements.create!(
          movement_type: "receipt",
          quantity: quantity,
          quantity_before: quantity_before,
          quantity_after: new_quantity,
          reason: reason || "Stock received",
          reference_type: reference_type,
          reference_id: reference_id,
          metadata: metadata
        )

        publish_event(:stock_received, inventory_item, movement)

        { item: inventory_item, movement: movement }
      end
    end

    # Reserve stock for an order
    def reserve_stock(inventory_item, quantity:, reference_type: nil, reference_id: nil, metadata: {})
      raise ArgumentError, "Quantity must be positive" if quantity <= 0

      ActiveRecord::Base.transaction do
        inventory_item.lock!

        unless inventory_item.can_reserve?(quantity)
          raise InventoryItem::InsufficientStockError,
                "Insufficient stock to reserve #{quantity} units (available: #{inventory_item.quantity_available})"
        end

        quantity_before = inventory_item.quantity_on_hand
        reservation_id = generate_reservation_id

        inventory_item.update!(quantity_reserved: inventory_item.quantity_reserved + quantity)

        movement = inventory_item.stock_movements.create!(
          movement_type: "reservation",
          quantity: -quantity, # Negative to indicate reduction in available
          quantity_before: quantity_before,
          quantity_after: inventory_item.quantity_on_hand,
          reason: "Stock reserved",
          reference_type: reference_type,
          reference_id: reference_id,
          metadata: metadata.merge(reservation_id: reservation_id)
        )

        publish_event(:stock_reserved, inventory_item, movement)

        { item: inventory_item, movement: movement, reservation_id: reservation_id }
      end
    end

    # Release a reservation (cancel order, etc.)
    def release_reservation(inventory_item, quantity:, reference_type: nil, reference_id: nil, metadata: {})
      raise ArgumentError, "Quantity must be positive" if quantity <= 0

      if quantity > inventory_item.quantity_reserved
        raise InventoryItem::InsufficientReservationError,
              "Cannot release #{quantity} units (reserved: #{inventory_item.quantity_reserved})"
      end

      ActiveRecord::Base.transaction do
        inventory_item.lock!

        quantity_before = inventory_item.quantity_on_hand

        inventory_item.update!(quantity_reserved: inventory_item.quantity_reserved - quantity)

        movement = inventory_item.stock_movements.create!(
          movement_type: "release",
          quantity: quantity, # Positive to indicate return to available
          quantity_before: quantity_before,
          quantity_after: inventory_item.quantity_on_hand,
          reason: "Reservation released",
          reference_type: reference_type,
          reference_id: reference_id,
          metadata: metadata
        )

        publish_event(:reservation_released, inventory_item, movement)

        { item: inventory_item, movement: movement }
      end
    end

    # Commit a reservation (fulfill order)
    def commit_reservation(inventory_item, quantity:, reference_type: nil, reference_id: nil, metadata: {})
      raise ArgumentError, "Quantity must be positive" if quantity <= 0

      if quantity > inventory_item.quantity_reserved
        raise InventoryItem::InsufficientReservationError,
              "Cannot commit #{quantity} units (reserved: #{inventory_item.quantity_reserved})"
      end

      ActiveRecord::Base.transaction do
        inventory_item.lock!

        quantity_before = inventory_item.quantity_on_hand

        inventory_item.update!(
          quantity_on_hand: inventory_item.quantity_on_hand - quantity,
          quantity_reserved: inventory_item.quantity_reserved - quantity
        )

        movement = inventory_item.stock_movements.create!(
          movement_type: "commit",
          quantity: -quantity,
          quantity_before: quantity_before,
          quantity_after: inventory_item.quantity_on_hand,
          reason: "Reservation committed (sold)",
          reference_type: reference_type,
          reference_id: reference_id,
          metadata: metadata
        )

        publish_event(:reservation_committed, inventory_item, movement)

        { item: inventory_item, movement: movement }
      end
    end

    # Transfer stock between locations
    def transfer_stock(source_item, destination_item, quantity:, reference_type: nil, reference_id: nil, metadata: {})
      raise ArgumentError, "Quantity must be positive" if quantity <= 0
      raise ArgumentError, "Source and destination must be different" if source_item.id == destination_item.id

      unless source_item.can_fulfill?(quantity)
        raise InventoryItem::InsufficientStockError,
              "Insufficient stock to transfer #{quantity} units (available: #{source_item.quantity_available})"
      end

      ActiveRecord::Base.transaction do
        # Lock both items to prevent deadlocks (order by id)
        items = [source_item, destination_item].sort_by(&:id)
        items.each(&:lock!)

        source_quantity_before = source_item.quantity_on_hand
        dest_quantity_before = destination_item.quantity_on_hand

        source_item.update!(quantity_on_hand: source_item.quantity_on_hand - quantity)
        destination_item.update!(quantity_on_hand: destination_item.quantity_on_hand + quantity)

        transfer_metadata = metadata.merge(
          transfer_id: SecureRandom.uuid,
          source_location: source_item.location,
          destination_location: destination_item.location
        )

        source_movement = source_item.stock_movements.create!(
          movement_type: "transfer_out",
          quantity: -quantity,
          quantity_before: source_quantity_before,
          quantity_after: source_item.quantity_on_hand,
          reason: "Transfer to #{destination_item.location}",
          reference_type: reference_type,
          reference_id: reference_id,
          metadata: transfer_metadata
        )

        dest_movement = destination_item.stock_movements.create!(
          movement_type: "transfer_in",
          quantity: quantity,
          quantity_before: dest_quantity_before,
          quantity_after: destination_item.quantity_on_hand,
          reason: "Transfer from #{source_item.location}",
          reference_type: reference_type,
          reference_id: reference_id,
          metadata: transfer_metadata
        )

        publish_event(:stock_transferred, source_item, source_movement)

        {
          source_item: source_item,
          destination_item: destination_item,
          source_movement: source_movement,
          destination_movement: dest_movement,
          transfer_id: transfer_metadata[:transfer_id]
        }
      end
    end

    # Check stock availability
    def check_availability(sku, quantity:, location: nil)
      items = InventoryItem.by_sku(sku)
      items = items.by_location(location) if location.present?

      total_available = items.sum(&:quantity_available)
      backorderable = items.any?(&:backorderable?)

      {
        sku: sku,
        requested_quantity: quantity,
        total_available: total_available,
        is_available: total_available >= quantity || backorderable,
        backorderable: backorderable,
        locations: items.map do |item|
          {
            location: item.location,
            available: item.quantity_available,
            backorderable: item.backorderable?
          }
        end
      }
    end

    # Bulk availability check
    def check_bulk_availability(items)
      items.map do |item_request|
        check_availability(
          item_request[:sku],
          quantity: item_request[:quantity],
          location: item_request[:location]
        )
      end
    end

    # Perform inventory count adjustment
    def count_adjustment(inventory_item, actual_count:, reason: nil, metadata: {})
      ActiveRecord::Base.transaction do
        inventory_item.lock!

        quantity_before = inventory_item.quantity_on_hand
        difference = actual_count - quantity_before

        return { item: inventory_item, movement: nil, difference: 0 } if difference.zero?

        inventory_item.update!(quantity_on_hand: actual_count)

        movement = inventory_item.stock_movements.create!(
          movement_type: "count_adjustment",
          quantity: difference,
          quantity_before: quantity_before,
          quantity_after: actual_count,
          reason: reason || "Inventory count adjustment",
          metadata: metadata.merge(
            counted_at: Time.current.iso8601,
            expected: quantity_before,
            actual: actual_count
          )
        )

        publish_event(:inventory_counted, inventory_item, movement)

        { item: inventory_item, movement: movement, difference: difference }
      end
    end

    private

    def generate_reservation_id
      "RES-#{SecureRandom.hex(8).upcase}"
    end

    def publish_event(event_type, inventory_item, movement)
      # In a full implementation, this would publish to an event bus
      # e.g., RailsEventStore, Kafka, RabbitMQ, etc.
      Rails.logger.info(
        "Inventory event: #{event_type}",
        {
          event_type: event_type,
          sku: inventory_item.sku,
          location: inventory_item.location,
          movement_id: movement.id,
          movement_type: movement.movement_type,
          quantity: movement.quantity
        }
      )

      # Example: EventBus.publish(event_type, { inventory_item: inventory_item, movement: movement })
    end
  end
end
