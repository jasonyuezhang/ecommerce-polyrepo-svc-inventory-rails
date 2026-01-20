CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "inventory_items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "sku" varchar NOT NULL, "location" varchar DEFAULT 'default' NOT NULL, "quantity_on_hand" integer DEFAULT 0 NOT NULL, "quantity_reserved" integer DEFAULT 0 NOT NULL, "reorder_point" integer DEFAULT 0, "reorder_quantity" integer DEFAULT 0, "backorderable" boolean DEFAULT 0 NOT NULL, "metadata" text DEFAULT '{}' NOT NULL, "lock_version" integer DEFAULT 0 NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE sqlite_sequence(name,seq);
CREATE UNIQUE INDEX "idx_inventory_items_sku_location" ON "inventory_items" ("sku", "location");
CREATE INDEX "idx_inventory_items_sku" ON "inventory_items" ("sku");
CREATE INDEX "idx_inventory_items_location" ON "inventory_items" ("location");
CREATE INDEX "idx_inventory_items_backorderable" ON "inventory_items" ("backorderable");
CREATE TABLE IF NOT EXISTS "stock_movements" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "inventory_item_id" integer NOT NULL, "movement_type" varchar NOT NULL, "quantity" integer NOT NULL, "quantity_before" integer NOT NULL, "quantity_after" integer NOT NULL, "reason" varchar, "reference_type" varchar, "reference_id" varchar, "metadata" text DEFAULT '{}' NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_05ce662104"
FOREIGN KEY ("inventory_item_id")
  REFERENCES "inventory_items" ("id")
);
CREATE INDEX "index_stock_movements_on_inventory_item_id" ON "stock_movements" ("inventory_item_id");
CREATE INDEX "idx_stock_movements_item" ON "stock_movements" ("inventory_item_id");
CREATE INDEX "idx_stock_movements_type" ON "stock_movements" ("movement_type");
CREATE INDEX "idx_stock_movements_created" ON "stock_movements" ("created_at");
CREATE INDEX "idx_stock_movements_reference" ON "stock_movements" ("reference_type", "reference_id");
CREATE INDEX "idx_stock_movements_item_type" ON "stock_movements" ("inventory_item_id", "movement_type");
INSERT INTO "schema_migrations" (version) VALUES
('20240101000002'),
('20240101000001');

