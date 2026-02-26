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
#  stock_count        :integer          not null, default: 0
#  held_count         :integer          not null, default: 0
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
  validates :stock_count, numericality: { only_integer: true }
  validates :held_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reorder_point, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reorder_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Scopes
  scope :by_sku, ->(sku) { where(sku: sku) }
  scope :by_location, ->(location) { where(location: location) }
  scope :low_stock, -> { where("stock_count - held_count <= reorder_point") }
  scope :out_of_stock, -> { where("stock_count - held_count <= 0") }
  scope :in_stock, -> { where("stock_count - held_count > 0") }
  scope :backorderable, -> { where(backorderable: true) }

  # Callbacks
  after_save :check_reorder_point, if: :saved_change_to_stock_count?

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
  def available_count
    stock_count - held_count
  end

  def available_to_promise
    backorderable? ? Float::INFINITY : available_count
  end

  def in_stock?
    available_count.positive?
  end

  def low_stock?
    reorder_point.present? && available_count <= reorder_point
  end

  def out_of_stock?
    available_count <= 0
  end

  # Stock operations
  def adjust_stock!(quantity, reason: nil, reference: nil, metadata: {})
    transaction do
      lock!

      new_quantity = stock_count + quantity

      unless backorderable? || new_quantity >= held_count
        raise InsufficientStockError, "Cannot reduce stock below reserved quantity"
      end

      update!(stock_count: new_quantity)

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
      update!(stock_count: stock_count + quantity)

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

      update!(held_count: held_count + quantity)

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
    raise InsufficientReservationError, "Cannot release more than reserved" if quantity > held_count

    transaction do
      lock!
      update!(held_count: held_count - quantity)

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
    raise InsufficientReservationError, "Cannot commit more than reserved" if quantity > held_count

    transaction do
      lock!
      update!(
        stock_count: stock_count - quantity,
        held_count: held_count - quantity
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
    raise InsufficientStockError, "Insufficient available stock to transfer" unless can_fulfill?(quantity)

    transaction do
      lock!
      destination_item.lock!

      update!(stock_count: stock_count - quantity)
      destination_item.update!(stock_count: destination_item.stock_count + quantity)

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
    backorderable? || available_count >= quantity
  end

  def can_fulfill?(quantity)
    backorderable? || available_count >= quantity
  end

  # Record a stock movement
  def record_movement(movement_type:, quantity:, reason: nil, reference: nil, metadata: {})
    stock_movements.create!(
      movement_type: movement_type,
      quantity: quantity,
      quantity_before: stock_count_before_last_save || stock_count,
      quantity_after: stock_count,
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
      by_sku(sku).sum(:stock_count)
    end

    def total_available_for_sku(sku)
      by_sku(sku).sum("stock_count - held_count")
    end

    def aggregate_by_sku
      group(:sku).select(
        :sku,
        "SUM(stock_count) as total_on_hand",
        "SUM(held_count) as total_reserved",
        "SUM(stock_count - held_count) as total_available"
      )
    end
  end

  private

  def check_reorder_point
    return unless low_stock? && reorder_quantity.to_i.positive?

    # Trigger reorder notification (could be event, job, etc.)
    Rails.logger.info("Low stock alert: SKU #{sku} at #{location} - #{available_count} units available")

    # In a real implementation, you might:
    # - Publish an event: EventBus.publish(LowStockDetected.new(sku: sku, location: location))
    # - Queue a job: ReorderJob.perform_later(id)
  end

  # Custom exceptions
  class InsufficientStockError < StandardError; end
  class InsufficientReservationError < StandardError; end
end
