# Quick Start Guide

Get the gRPC server running in 5 minutes.

## Prerequisites

```bash
# Check Ruby version (need 3.2+)
ruby -v

# Check bundler is installed
bundle -v
```

## Step 1: Clone and Setup

```bash
# If you don't have the repo yet
git clone https://github.com/jasonyuezhang/ecommerce-polyrepo
cd ecommerce-polyrepo/svc-inventory-rails

# Initialize proto-schemas submodule
git submodule update --init --recursive
```

## Step 2: Install Dependencies

```bash
bundle install
```

## Step 3: Database Setup

```bash
# Create and migrate database
bundle exec rails db:create db:migrate

# Optional: Seed with sample data
bundle exec rails db:seed
```

## Step 4: Generate Proto Stubs

```bash
bundle exec rake grpc:generate
```

You should see:
```
Generating Ruby gRPC stubs from proto files...
Successfully generated gRPC stubs in lib/proto
```

## Step 5: Start Servers

### Option A: Both servers together (recommended)

```bash
bin/start-dual-server
```

You should see:
```
🚀 Starting Inventory Service (Rails REST + gRPC)
✅ Rails REST API started (PID: 12345)
✅ gRPC server started (PID: 12346)
🎉 All servers running!

Press Ctrl+C to stop both servers
```

### Option B: Separate terminals

Terminal 1:
```bash
bundle exec rails server -p 3000
```

Terminal 2:
```bash
bin/grpc-server
```

## Step 6: Verify It Works

### Test REST API

```bash
curl http://localhost:3000/health
```

Expected: `{"status":"ok"}`

### Test gRPC (requires grpcurl)

```bash
# Install grpcurl (macOS)
brew install grpcurl

# Health check
grpcurl -plaintext localhost:50051 \
  inventory.v1.InventoryService/HealthCheck
```

Expected:
```json
{
  "status": "HEALTH_STATUS_HEALTHY",
  "message": "Inventory service is healthy"
}
```

### Or use the test client

```bash
bin/grpc-test-client
```

## Common Operations

### Create test inventory item

```bash
# Via Rails console
bundle exec rails console

> InventoryItem.create!(
    sku: "PROD-001",
    location: "warehouse-1",
    quantity_on_hand: 100,
    quantity_reserved: 0
  )
```

### Query via gRPC

```bash
grpcurl -plaintext \
  -d '{"sku": "PROD-001", "warehouse_id": "warehouse-1"}' \
  localhost:50051 \
  inventory.v1.InventoryService/GetStockBySku
```

### Adjust stock

```bash
grpcurl -plaintext \
  -d '{
    "listing_id": "PROD-001",
    "warehouse_id": "warehouse-1",
    "quantity_delta": 50,
    "reason": "Stock receipt"
  }' \
  localhost:50051 \
  inventory.v1.InventoryService/AdjustStock
```

### Reserve stock

```bash
grpcurl -plaintext \
  -d '{
    "order_id": "ORDER-123",
    "items": [
      {
        "listing_id": "PROD-001",
        "quantity": 5
      }
    ]
  }' \
  localhost:50051 \
  inventory.v1.InventoryService/ReserveStock
```

## Troubleshooting

### "Proto files not generated"

```bash
# Solution:
bundle exec rake grpc:generate
```

### "Port already in use"

```bash
# Find process using port 50051
lsof -i :50051

# Kill it
kill -9 <PID>

# Or use different port
GRPC_PORT=50052 bin/grpc-server
```

### "Database does not exist"

```bash
# Solution:
bundle exec rails db:create db:migrate
```

### "Cannot connect to database"

Check PostgreSQL is running:
```bash
# macOS
brew services start postgresql@14

# Linux
sudo systemctl start postgresql
```

## Next Steps

- Read [GRPC_SETUP.md](./GRPC_SETUP.md) for detailed documentation
- Read [IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md) for architecture details
- Check [README.md](./README.md) for API documentation
- Run tests: `bundle exec rspec spec/grpc/`

## Quick Reference

| Command | Purpose |
|---------|---------|
| `bundle exec rake grpc:generate` | Generate proto stubs |
| `bin/start-dual-server` | Start both REST + gRPC |
| `bin/grpc-server` | Start gRPC only |
| `bin/grpc-test-client` | Test gRPC endpoints |
| `bundle exec rails console` | Interactive console |
| `bundle exec rspec` | Run tests |

## Ports

- **3000** - REST API
- **50051** - gRPC server

## Environment Variables

```bash
# Copy example file
cp .env.example .env

# Key variables:
GRPC_PORT=50051
DATABASE_URL=postgresql://user:pass@localhost:5432/inventory_dev
```

## Docker

```bash
# Build
docker build -t inventory-service .

# Run
docker run -p 3000:3000 -p 50051:50051 \
  -e DATABASE_URL=postgresql://... \
  inventory-service
```

## Help

For issues or questions:
1. Check [GRPC_SETUP.md](./GRPC_SETUP.md) troubleshooting section
2. Check logs: `tail -f log/development.log`
3. Open issue on GitHub

---

**You're ready!** 🚀 The gRPC server is now running and ready to handle requests.
