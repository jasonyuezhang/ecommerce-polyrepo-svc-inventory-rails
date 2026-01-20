# frozen_string_literal: true

class CreateStockMovements < ActiveRecord::Migration[7.1]
  def change
    # Determine types based on database adapter
    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      id_type = :uuid
      ref_type = :uuid
    else
      id_type = :primary_key
      ref_type = :integer
    end

    create_table :stock_movements, id: id_type do |t|
      # Reference to inventory item
      t.references :inventory_item, null: false, foreign_key: true, type: ref_type

      # Movement details
      t.string :movement_type, null: false
      t.integer :quantity, null: false
      t.integer :quantity_before, null: false
      t.integer :quantity_after, null: false

      # Human-readable reason
      t.string :reason

      # Polymorphic reference (order, transfer, adjustment, etc.)
      t.string :reference_type
      t.string :reference_id

      # Flexible metadata storage
      if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
        t.jsonb :metadata, default: {}, null: false
      else
        t.text :metadata, default: "{}", null: false
      end

      # Only created_at - movements are immutable
      t.datetime :created_at, null: false
    end

    # Index for querying movements by item
    add_index :stock_movements, :inventory_item_id, name: "idx_stock_movements_item"

    # Index for querying by movement type
    add_index :stock_movements, :movement_type, name: "idx_stock_movements_type"

    # Index for time-based queries
    add_index :stock_movements, :created_at, name: "idx_stock_movements_created"

    # Composite index for polymorphic reference lookups
    add_index :stock_movements, [:reference_type, :reference_id],
              name: "idx_stock_movements_reference"

    # Composite index for item + type queries
    add_index :stock_movements, [:inventory_item_id, :movement_type],
              name: "idx_stock_movements_item_type"

    # PostgreSQL-specific indexes
    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      # JSONB GIN index for metadata queries
      add_index :stock_movements, :metadata, using: :gin, name: "idx_stock_movements_metadata"

      # Index for reservation_id lookups (stored in metadata)
      add_index :stock_movements, "(metadata->>'reservation_id')",
                name: "idx_stock_movements_reservation_id",
                where: "metadata->>'reservation_id' IS NOT NULL"

      # Check constraint for valid movement types
      execute <<-SQL
        ALTER TABLE stock_movements
        ADD CONSTRAINT chk_movement_type_valid
        CHECK (movement_type IN (
          'receipt',
          'sale',
          'adjustment',
          'transfer_in',
          'transfer_out',
          'reservation',
          'release',
          'commit',
          'return',
          'damage',
          'loss',
          'found',
          'count_adjustment'
        ));
      SQL
    end
  end
end
