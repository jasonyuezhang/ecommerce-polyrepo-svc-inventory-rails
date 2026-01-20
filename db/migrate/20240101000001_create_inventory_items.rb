# frozen_string_literal: true

class CreateInventoryItems < ActiveRecord::Migration[7.1]
  def change
    # Enable UUID extension for PostgreSQL
    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")
      id_type = :uuid
      metadata_type = :jsonb
    else
      id_type = :primary_key
      metadata_type = :text
    end

    create_table :inventory_items, id: id_type do |t|
      # Core attributes
      t.string :sku, null: false
      t.string :location, null: false, default: "default"

      # Quantity tracking
      t.integer :quantity_on_hand, null: false, default: 0
      t.integer :quantity_reserved, null: false, default: 0

      # Reorder settings
      t.integer :reorder_point, default: 0
      t.integer :reorder_quantity, default: 0
      t.boolean :backorderable, default: false, null: false

      # Flexible metadata storage
      if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
        t.jsonb :metadata, default: {}, null: false
      else
        t.text :metadata, default: "{}", null: false
      end

      # Optimistic locking
      t.integer :lock_version, default: 0, null: false

      t.timestamps
    end

    # Unique constraint: one inventory item per SKU per location
    add_index :inventory_items, [:sku, :location], unique: true, name: "idx_inventory_items_sku_location"

    # Query performance indexes
    add_index :inventory_items, :sku, name: "idx_inventory_items_sku"
    add_index :inventory_items, :location, name: "idx_inventory_items_location"

    # PostgreSQL-specific indexes
    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      # Low stock query optimization
      add_index :inventory_items,
                "(quantity_on_hand - quantity_reserved)",
                name: "idx_inventory_items_available",
                using: :btree

      # Backorderable items lookup
      add_index :inventory_items, :backorderable,
                where: "backorderable = true",
                name: "idx_inventory_items_backorderable"

      # JSONB GIN index for metadata queries
      add_index :inventory_items, :metadata, using: :gin, name: "idx_inventory_items_metadata"
    else
      # SQLite fallback indexes
      add_index :inventory_items, :backorderable, name: "idx_inventory_items_backorderable"
    end

    # Check constraints for data integrity (PostgreSQL only)
    if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
      execute <<-SQL
        ALTER TABLE inventory_items
        ADD CONSTRAINT chk_quantity_reserved_non_negative
        CHECK (quantity_reserved >= 0);
      SQL

      execute <<-SQL
        ALTER TABLE inventory_items
        ADD CONSTRAINT chk_reorder_point_non_negative
        CHECK (reorder_point >= 0 OR reorder_point IS NULL);
      SQL

      execute <<-SQL
        ALTER TABLE inventory_items
        ADD CONSTRAINT chk_reorder_quantity_non_negative
        CHECK (reorder_quantity >= 0 OR reorder_quantity IS NULL);
      SQL
    end
  end
end
