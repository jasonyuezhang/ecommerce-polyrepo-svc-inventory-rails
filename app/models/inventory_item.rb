# frozen_string_literal: true

# Represents an inventory item at a specific location.
# Based on patterns from Solidus Stock Items and RailsEventStore inventory domain.
#
# == Schema Information
#
# Table name: inventory_items
#
#  id                 :uuid             not null, primary key
#  sku                :string           not null
#  location           :string           not null, default: "default"
#  quantity_on_hand   :integer          not null, default: 0
#  quantity_reserved  :integer          not null, default: 0
#  reorder_point      :integer          default: 0
#  reorder_quantity   :integer          default: 0
#  backorderable      :boolean          default: false
#  metadata           :jsonb            default: {}
#  lock_version       :integer          default: 0
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class InventoryItem < ApplicationRecord
  # Associations
  has_many :stock_movements, dependent: :destroy

  # Validations
  validates :sku, presence: true
  validates :location, presence: true
  validates :sku, uniqueness: { scope: :location, message: "already exists at this location" }
  validates :quantity_on_hand, numericality: { only_integer: true }
  validates :quantity_reserved, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reorder_point, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reorder_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Scopes
  scope :by_sku, ->(sku) { where(sku: sku) }
  scope :by_location, ->(location) { where(location: location) }
  scope :low_stock, -> { where("quantity_on_hand - quantity_reserved <= reorder_point") }
  scope :out_of_stock, -> { where("quantity_on_hand - quantity_reserved <= 0") }
  scope :in_stock, -> { where("quantity_on_hand - quantity_reserved > 0") }
  scope :backorderable, -> { where(backorderable: true) }

  # Callbacks
  after_save :check_reorder_point, if: :saved_change_to_quantity_on_hand?

  # Movement types
  MOVEMENT_TYPES = %w[
    receipt
    sale
    adjustment
    transfer_in
    transfer_out
    reservation
    release
    commit
    return
    damage
    loss
    found
    count_adjustment
  ].freeze

  # Computed attributes
  def quantity_available
    quantity_on_hand - quantity_reserved
  end

  def available_to_promise
    backorderable? ? Float::INFINITY : quantity_available
  end

  def in_stock?
    quantity_available.positive?
  end

  def low_stock?
    reorder_point.present? && quantity_available <= reorder_point
  end

  def out_of_stock?
    quantity_available <= 0
  end

  # Stock operations
  def adjust_stock!(quantity, reason: nil, reference: nil, metadata: {})
    transaction do
      lock!

      new_quantity = quantity_on_hand + quantity

      unless backorderable? || new_quantity >= quantity_reserved
        raise InsufficientStockError, "Cannot reduce stock below reserved quantity"
      end

      update!(quantity_on_hand: new_quantity)

      record_movement(
        movement_type: "adjustment",
        quantity: quantity,
        reason: reason,
        reference: reference,
        metadata: metadata
      )

      self
    end
  end

  def receive_stock!(quantity, reason: nil, reference: nil, metadata: {})
    raise ArgumentError, "Quantity must be positive" if quantity <= 0

    transaction do
      lock!
      update!(quantity_on_hand: quantity_on_hand + quantity)

      record_movement(
        movement_type: "receipt",
        quantity: quantity,
        reason: reason,
        reference: reference,
        metadata: metadata
      )

      self
    end
  end

  def reserve_stock!(quantity, reference: nil, metadata: {})
    raise ArgumentError, "Quantity must be positive" if quantity <= 0

    transaction do
      lock!

      unless can_reserve?(quantity)
        raise InsufficientStockError, "Insufficient stock to reserve #{quantity} units"
      end

      update!(quantity_reserved: quantity_reserved + quantity)

      record_movement(
        movement_type: "reservation",
        quantity: -quantity,
        reason: "Stock reserved",
        reference: reference,
        metadata: metadata
      )

      self
    end
  end

  def release_reservation!(quantity, reference: nil, metadata: {})
    raise ArgumentError, "Quantity must be positive" if quantity <= 0
    raise InsufficientReservationError, "Cannot release more than reserved" if quantity > quantity_reserved

    transaction do
      lock!
      update!(quantity_reserved: quantity_reserved - quantity)

      record_movement(
        movement_type: "release",
        quantity: quantity,
        reason: "Reservation released",
        reference: reference,
        metadata: metadata
      )

      self
    end
  end

  def commit_reservation!(quantity, reference: nil, metadata: {})
    raise ArgumentError, "Quantity must be positive" if quantity <= 0
    raise InsufficientReservationError, "Cannot commit more than reserved" if quantity > quantity_reserved

    transaction do
      lock!
      update!(
        quantity_on_hand: quantity_on_hand - quantity,
        quantity_reserved: quantity_reserved - quantity
      )

      record_movement(
        movement_type: "commit",
        quantity: -quantity,
        reason: "Reservation committed (sold)",
        reference: reference,
        metadata: metadata
      )

      self
    end
  end

  def transfer_to!(destination_item, quantity, reference: nil, metadata: {})
    raise ArgumentError, "Quantity must be positive" if quantity <= 0
    raise InsufficientStockError, "Insufficient stock to transfer" unless can_fulfill?(quantity)

    transaction do
      lock!
      destination_item.lock!

      update!(quantity_on_hand: quantity_on_hand - quantity)
      destination_item.update!(quantity_on_hand: destination_item.quantity_on_hand + quantity)

      record_movement(
        movement_type: "transfer_out",
        quantity: -quantity,
        reason: "Transfer to #{destination_item.location}",
        reference: reference,
        metadata: metadata.merge(destination_location: destination_item.location)
      )

      destination_item.record_movement(
        movement_type: "transfer_in",
        quantity: quantity,
        reason: "Transfer from #{location}",
        reference: reference,
        metadata: metadata.merge(source_location: location)
      )

      self
    end
  end

  # Query methods
  def can_reserve?(quantity)
    backorderable? || quantity_available >= quantity
  end

  def can_fulfill?(quantity)
    backorderable? || quantity_available >= quantity
  end

  # Record a stock movement
  def record_movement(movement_type:, quantity:, reason: nil, reference: nil, metadata: {})
    stock_movements.create!(
      movement_type: movement_type,
      quantity: quantity,
      quantity_before: quantity_on_hand_before_last_save || quantity_on_hand,
      quantity_after: quantity_on_hand,
      reason: reason,
      reference_type: reference&.class&.name,
      reference_id: reference.respond_to?(:id) ? reference.id : reference,
      metadata: metadata
    )
  end

  # Class methods
  class << self
    def find_by_sku!(sku, location: "default")
      find_by!(sku: sku, location: location)
    end

    def total_quantity_for_sku(sku)
      by_sku(sku).sum(:quantity_on_hand)
    end

    def total_available_for_sku(sku)
      by_sku(sku).sum("quantity_on_hand - quantity_reserved")
    end

    def aggregate_by_sku
      group(:sku).select(
        :sku,
        "SUM(quantity_on_hand) as total_on_hand",
        "SUM(quantity_reserved) as total_reserved",
        "SUM(quantity_on_hand - quantity_reserved) as total_available"
      )
    end
  end

  private

  def check_reorder_point
    return unless low_stock? && reorder_quantity.to_i.positive?

    # Trigger reorder notification (could be event, job, etc.)
    Rails.logger.info("Low stock alert: SKU #{sku} at #{location} - #{quantity_available} units available")

    # In a real implementation, you might:
    # - Publish an event: EventBus.publish(LowStockDetected.new(sku: sku, location: location))
    # - Queue a job: ReorderJob.perform_later(id)
  end

  # Custom exceptions
  class InsufficientStockError < StandardError; end
  class InsufficientReservationError < StandardError; end
end
