# Inventory Service (Rails)

A minimal Ruby on Rails microservice for managing inventory levels, stock movements, and reservations. Provides both REST API and gRPC interfaces.

## Features

- **Inventory Management**: Track stock levels per SKU and location
- **Stock Movements**: Record all inventory changes with audit trail
- **Reservations**: Reserve stock for pending orders
- **Dual Interface**: REST API and gRPC server

## Architecture

Based on patterns from RailsEventStore/ecommerce and Solidus inventory modules:

- Event-driven stock tracking
- Location-aware inventory
- Audit trail for all movements
- Optimistic locking for concurrency

## Requirements

- Ruby 3.2+
- Rails 7.1+
- PostgreSQL 14+
- gRPC

## Setup

```bash
# Install dependencies
bundle install

# Setup database
rails db:create db:migrate

# Start REST server
rails server -p 3000

# Start gRPC server (separate process)
ruby app/grpc/inventory_server.rb
```

## Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

## REST API Endpoints

### Inventory Items

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/inventory` | List all inventory items |
| GET | `/api/v1/inventory/:sku` | Get inventory by SKU |
| POST | `/api/v1/inventory` | Create inventory item |
| PATCH | `/api/v1/inventory/:sku` | Update inventory item |
| DELETE | `/api/v1/inventory/:sku` | Delete inventory item |

### Stock Operations

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/inventory/:sku/adjust` | Adjust stock level |
| POST | `/api/v1/inventory/:sku/reserve` | Reserve stock |
| POST | `/api/v1/inventory/:sku/release` | Release reservation |
| POST | `/api/v1/inventory/:sku/commit` | Commit reservation |
| GET | `/api/v1/inventory/:sku/movements` | Get stock movements |

## gRPC Interface

The gRPC server runs on port 50051 by default.

### Services

```protobuf
service InventoryService {
  rpc GetStock(GetStockRequest) returns (StockResponse);
  rpc AdjustStock(AdjustStockRequest) returns (StockResponse);
  rpc ReserveStock(ReserveStockRequest) returns (ReservationResponse);
  rpc ReleaseReservation(ReleaseRequest) returns (StockResponse);
  rpc CommitReservation(CommitRequest) returns (StockResponse);
}
```

## Models

### InventoryItem

- `sku` - Unique product identifier
- `location` - Warehouse/store location
- `quantity_on_hand` - Current stock level
- `quantity_reserved` - Reserved for orders
- `quantity_available` - Computed available stock
- `reorder_point` - Low stock threshold
- `reorder_quantity` - Default reorder amount

### StockMovement

- `inventory_item_id` - Reference to inventory item
- `movement_type` - Type of movement (receipt, sale, adjustment, reservation, etc.)
- `quantity` - Amount changed (positive or negative)
- `reference_type` - Polymorphic reference type
- `reference_id` - Polymorphic reference ID
- `reason` - Human-readable reason
- `metadata` - Additional JSON data

## Docker

```bash
# Build image
docker build -t svc-inventory-rails .

# Run container
docker run -p 3000:3000 -p 50051:50051 svc-inventory-rails
```

## Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/models/inventory_item_spec.rb
```

## License

MIT
