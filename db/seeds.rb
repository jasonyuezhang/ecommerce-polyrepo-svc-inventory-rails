# frozen_string_literal: true

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "Seeding inventory items..."

# Sample inventory items
items = [
  { sku: "WIDGET-001", location: "warehouse-east", quantity_on_hand: 100, reorder_point: 20, reorder_quantity: 50 },
  { sku: "WIDGET-001", location: "warehouse-west", quantity_on_hand: 75, reorder_point: 15, reorder_quantity: 40 },
  { sku: "GADGET-002", location: "warehouse-east", quantity_on_hand: 50, reorder_point: 10, reorder_quantity: 25, backorderable: true },
  { sku: "GADGET-002", location: "warehouse-west", quantity_on_hand: 30, reorder_point: 10, reorder_quantity: 25, backorderable: true },
  { sku: "THING-003", location: "warehouse-east", quantity_on_hand: 200, reorder_point: 50, reorder_quantity: 100 },
  { sku: "DOOHICKEY-004", location: "warehouse-east", quantity_on_hand: 15, reorder_point: 20, reorder_quantity: 30 },
  { sku: "GIZMO-005", location: "warehouse-east", quantity_on_hand: 0, reorder_point: 5, reorder_quantity: 20, backorderable: true }
]

items.each do |item_attrs|
  item = InventoryItem.find_or_initialize_by(sku: item_attrs[:sku], location: item_attrs[:location])
  item.assign_attributes(item_attrs)
  item.save!
  puts "  Created/Updated: #{item.sku} at #{item.location} (#{item.quantity_on_hand} units)"
end

puts "Seeding complete!"
puts "  Total inventory items: #{InventoryItem.count}"
puts "  Total stock movements: #{StockMovement.count}"
