# gRPC Server Setup Guide

This guide explains how to set up and run the gRPC server for the Inventory service.

## Overview

The inventory service provides both:
- **REST API** on port 3000
- **gRPC API** on port 50051

Both run simultaneously using the dual-server startup script.

## Prerequisites

1. **Ruby 3.2+** and bundler
2. **PostgreSQL** database
3. **Proto schemas** submodule initialized:
   ```bash
   git submodule update --init --recursive
   ```

## Quick Start

### Generate gRPC Stubs

First, generate Ruby code from proto files:

```bash
bundle exec rake grpc:generate
```

This creates Ruby classes in `lib/proto/` from the proto definitions.

### Start Both Servers

```bash
# Start both REST (port 3000) and gRPC (port 50051)
bin/start-dual-server
```

Or start them individually:

```bash
# Terminal 1: Rails REST API
bundle exec rails server -p 3000

# Terminal 2: gRPC server
bundle exec bin/grpc-server
```

## gRPC Service Implementation

### Available RPCs

Based on `proto-schemas/proto/inventory/v1/inventory.proto`:

#### Stock Operations
- `GetStockBySku` - Get stock information by SKU
- `AdjustStock` - Adjust stock levels (increase/decrease)
- `UpdateStock` - Update stock with field mask
- `SetStock` - Set absolute stock level

#### Reservation Operations
- `ReserveStock` - Reserve stock for orders
- `ReleaseReservation` - Cancel/release reservation
- `ConfirmReservation` - Confirm reservation (deduct from stock)
- `GetReservation` - Get reservation details
- `ListReservations` - List reservations

#### Analytics & Monitoring
- `HealthCheck` - Service health status
- `GetStockMovements` - Stock movement history
- `GetLowStockAlerts` - Low stock alerts
- `StreamStockUpdates` - Real-time stock updates (streaming)

### Implementation Details

The gRPC service (`app/grpc/inventory_grpc_server.rb`) maps proto RPCs to Rails models:

1. **InventoryItem** - Tracks stock levels per SKU/location
2. **StockMovement** - Immutable audit log of all stock changes
3. **InventoryService** - Business logic for stock operations

Key features:
- **Optimistic locking** - Prevents concurrent update conflicts
- **Transactional consistency** - All operations are atomic
- **Audit logging** - Complete history via StockMovement
- **Error handling** - Proper gRPC status codes

## Testing

### Using grpcurl

Install grpcurl:
```bash
brew install grpcurl  # macOS
```

Test health check:
```bash
grpcurl -plaintext \
  -import-path ../proto-schemas/proto \
  -proto inventory/v1/inventory.proto \
  localhost:50051 \
  inventory.v1.InventoryService/HealthCheck
```

Get stock by SKU:
```bash
grpcurl -plaintext \
  -import-path ../proto-schemas/proto \
  -proto inventory/v1/inventory.proto \
  -d '{"sku": "PROD-001", "warehouse_id": "default"}' \
  localhost:50051 \
  inventory.v1.InventoryService/GetStockBySku
```

Reserve stock:
```bash
grpcurl -plaintext \
  -import-path ../proto-schemas/proto \
  -proto inventory/v1/inventory.proto \
  -d '{
    "order_id": "ORDER-123",
    "items": [
      {
        "listing_id": "PROD-001",
        "quantity": 5
      }
    ],
    "expiration_seconds": 3600
  }' \
  localhost:50051 \
  inventory.v1.InventoryService/ReserveStock
```

## Docker Deployment

### Build Image

```bash
docker build -t inventory-service:latest .
```

### Run Container

```bash
docker run -d \
  -p 3000:3000 \
  -p 50051:50051 \
  -e DATABASE_URL=postgresql://user:pass@db:5432/inventory \
  -e RAILS_ENV=production \
  inventory-service:latest
```

### Docker Compose

```yaml
version: '3.8'
services:
  inventory:
    build: .
    ports:
      - "3000:3000"   # REST API
      - "50051:50051" # gRPC
    environment:
      DATABASE_URL: postgresql://postgres:password@postgres:5432/inventory
      RAILS_ENV: production
    depends_on:
      - postgres
```

## Kubernetes Deployment

The service exposes two ports in k8s:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: inventory-service
spec:
  ports:
    - name: http
      port: 3000
      targetPort: 3000
    - name: grpc
      port: 50051
      targetPort: 50051
  selector:
    app: inventory-service
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GRPC_PORT` | `50051` | gRPC server port |
| `GRPC_POOL_SIZE` | `30` | gRPC thread pool size |
| `RAILS_ENV` | `development` | Rails environment |
| `DATABASE_URL` | - | PostgreSQL connection string |

## Architecture

```
┌─────────────────────────────────────────┐
│         Inventory Service               │
│                                         │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Rails REST   │  │  gRPC Server    │ │
│  │  (Port 3000) │  │  (Port 50051)   │ │
│  └──────┬───────┘  └────────┬────────┘ │
│         │                   │          │
│         └───────┬───────────┘          │
│                 │                      │
│         ┌───────▼────────┐             │
│         │ Business Logic │             │
│         │ (InventoryService)           │
│         └───────┬────────┘             │
│                 │                      │
│         ┌───────▼────────┐             │
│         │     Models     │             │
│         │ InventoryItem  │             │
│         │ StockMovement  │             │
│         └───────┬────────┘             │
│                 │                      │
└─────────────────┼──────────────────────┘
                  │
         ┌────────▼────────┐
         │   PostgreSQL    │
         └─────────────────┘
```

## Proto Schema Updates

When proto files change:

1. Update proto-schemas submodule:
   ```bash
   cd ../proto-schemas
   git pull origin main
   cd ../svc-inventory-rails
   ```

2. Regenerate Ruby stubs:
   ```bash
   bundle exec rake grpc:generate
   ```

3. Update service implementation if needed

4. Restart servers:
   ```bash
   bin/start-dual-server
   ```

## Troubleshooting

### Proto files not found
```
ERROR: Proto files not generated. Run: rake grpc:generate
```
**Solution**: Ensure proto-schemas submodule is initialized and run `rake grpc:generate`

### Port already in use
```
Address already in use - bind(2) for "0.0.0.0" port 50051
```
**Solution**: Kill existing process or use different port:
```bash
GRPC_PORT=50052 bin/grpc-server
```

### Database connection errors
**Solution**: Ensure PostgreSQL is running and database exists:
```bash
bundle exec rails db:create db:migrate
```

## Performance Tuning

### gRPC Pool Size
Increase for high concurrency:
```bash
GRPC_POOL_SIZE=100 bin/grpc-server
```

### Database Connection Pool
Update `config/database.yml`:
```yaml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 30 } %>
```

## Monitoring

### Health Checks

REST:
```bash
curl http://localhost:3000/health
```

gRPC:
```bash
grpcurl -plaintext localhost:50051 inventory.v1.InventoryService/HealthCheck
```

### Metrics

Enable gRPC interceptors for metrics collection:
- Request count
- Response time
- Error rates
- Active connections

## Development

### Adding New RPCs

1. Update proto file in `proto-schemas`
2. Regenerate stubs: `rake grpc:generate`
3. Add method to `InventoryServiceImpl`
4. Add tests
5. Update documentation

### Code Organization

```
app/
  grpc/
    inventory_grpc_server.rb    # Service implementation
lib/
  proto/                        # Generated proto files
  tasks/
    grpc.rake                   # Rake tasks
bin/
  grpc-server                   # gRPC server launcher
  start-dual-server             # Dual server launcher
```

## References

- [gRPC Ruby Guide](https://grpc.io/docs/languages/ruby/)
- [Proto Schema Definitions](../proto-schemas/proto/inventory/v1/)
- [Rails gRPC Integration](https://github.com/grpc/grpc/tree/master/examples/ruby)
