# frozen_string_literal: true

# Represents a stock movement/transaction in the inventory system.
# Provides an immutable audit trail of all inventory changes.
# Based on patterns from Solidus and RailsEventStore event sourcing.
#
# == Schema Information
#
# Table name: stock_movements
#
#  id                :uuid             not null, primary key
#  inventory_item_id :uuid             not null
#  movement_type     :string           not null
#  quantity          :integer          not null
#  quantity_before   :integer          not null
#  quantity_after    :integer          not null
#  reason            :string
#  reference_type    :string
#  reference_id      :string
#  metadata          :jsonb            default: {}
#  created_at        :datetime         not null
#
class StockMovement < ApplicationRecord
  # Associations
  belongs_to :inventory_item

  # Validations
  validates :movement_type, presence: true, inclusion: { in: InventoryItem::MOVEMENT_TYPES }
  validates :quantity, presence: true, numericality: { only_integer: true }
  validates :quantity_before, presence: true, numericality: { only_integer: true }
  validates :quantity_after, presence: true, numericality: { only_integer: true }

  # Make movements immutable after creation
  validates :movement_type, :quantity, :quantity_before, :quantity_after,
            :inventory_item_id, readonly: true, on: :update

  # Scopes
  scope :by_type, ->(type) { where(movement_type: type) }
  scope :by_reference, ->(type, id) { where(reference_type: type, reference_id: id) }
  scope :inbound, -> { where("quantity > 0") }
  scope :outbound, -> { where("quantity < 0") }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Movement type categories
  INBOUND_TYPES = %w[receipt transfer_in return found adjustment].freeze
  OUTBOUND_TYPES = %w[sale transfer_out damage loss commit].freeze
  NEUTRAL_TYPES = %w[reservation release count_adjustment].freeze

  scope :receipts, -> { by_type("receipt") }
  scope :sales, -> { by_type("sale") }
  scope :adjustments, -> { by_type("adjustment") }
  scope :transfers, -> { where(movement_type: %w[transfer_in transfer_out]) }
  scope :reservations, -> { by_type("reservation") }
  scope :releases, -> { by_type("release") }
  scope :commits, -> { by_type("commit") }

  # Instance methods
  def inbound?
    quantity.positive?
  end

  def outbound?
    quantity.negative?
  end

  def absolute_quantity
    quantity.abs
  end

  def delta
    quantity_after - quantity_before
  end

  # Reference accessor
  def reference
    return nil unless reference_type.present? && reference_id.present?

    @reference ||= reference_type.constantize.find_by(id: reference_id)
  rescue NameError
    nil
  end

  # Human readable description
  def description
    case movement_type
    when "receipt"
      "Received #{absolute_quantity} units"
    when "sale"
      "Sold #{absolute_quantity} units"
    when "adjustment"
      quantity.positive? ? "Added #{quantity} units" : "Removed #{quantity.abs} units"
    when "transfer_in"
      "Transferred in #{absolute_quantity} units"
    when "transfer_out"
      "Transferred out #{absolute_quantity} units"
    when "reservation"
      "Reserved #{absolute_quantity} units"
    when "release"
      "Released #{absolute_quantity} units from reservation"
    when "commit"
      "Committed #{absolute_quantity} units from reservation"
    when "return"
      "Returned #{absolute_quantity} units"
    when "damage"
      "Damaged #{absolute_quantity} units"
    when "loss"
      "Lost #{absolute_quantity} units"
    when "found"
      "Found #{absolute_quantity} units"
    when "count_adjustment"
      "Inventory count adjustment: #{quantity.positive? ? '+' : ''}#{quantity} units"
    else
      "#{movement_type.humanize}: #{quantity} units"
    end
  end

  # Serialization
  def as_json(options = {})
    super(options.merge(
      methods: [:description, :absolute_quantity, :inbound?, :outbound?],
      except: [:updated_at]
    ))
  end

  # Class methods
  class << self
    # Aggregate movements by type for a period
    def summary_by_type(start_date: 30.days.ago, end_date: Time.current)
      in_period(start_date, end_date)
        .group(:movement_type)
        .select(
          :movement_type,
          "COUNT(*) as count",
          "SUM(quantity) as total_quantity",
          "SUM(ABS(quantity)) as absolute_total"
        )
    end

    # Net movement for a period
    def net_movement(start_date: 30.days.ago, end_date: Time.current)
      in_period(start_date, end_date).sum(:quantity)
    end

    # Audit trail for a specific reference
    def for_reference(reference_type:, reference_id:)
      by_reference(reference_type, reference_id).recent
    end

    # Build movement from event (for event sourcing pattern)
    def from_event(event)
      new(
        inventory_item_id: event.data[:inventory_item_id],
        movement_type: event.data[:movement_type],
        quantity: event.data[:quantity],
        quantity_before: event.data[:quantity_before],
        quantity_after: event.data[:quantity_after],
        reason: event.data[:reason],
        reference_type: event.data[:reference_type],
        reference_id: event.data[:reference_id],
        metadata: event.data[:metadata] || {}
      )
    end
  end

  private

  # Custom validator for immutable attributes
  class ReadonlyValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      if record.persisted? && record.send("#{attribute}_changed?")
        record.errors.add(attribute, "cannot be changed after creation")
      end
    end
  end
end
