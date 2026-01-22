# frozen_string_literal: true

require "rails_helper"
require "grpc"

# Load proto files
begin
  require_relative "../../lib/proto/inventory/v1/inventory_pb"
  require_relative "../../lib/proto/inventory/v1/inventory_services_pb"
  PROTO_AVAILABLE = true
rescue LoadError
  PROTO_AVAILABLE = false
end

RSpec.describe "Inventory gRPC Service", type: :request do
  before(:all) do
    skip "Proto files not generated. Run: rake grpc:generate" unless PROTO_AVAILABLE
  end

  let(:stub) do
    Inventory::V1::InventoryService::Stub.new(
      "localhost:#{ENV.fetch('GRPC_PORT', 50051)}",
      :this_channel_is_insecure
    )
  end

  describe "HealthCheck" do
    it "returns healthy status" do
      response = stub.health_check(Google::Protobuf::Empty.new)

      expect(response).to be_a(Common::V1::HealthCheckResponse)
      expect(response.status).to eq(Common::V1::HealthStatus::HEALTH_STATUS_HEALTHY)
    end
  end

  describe "AdjustStock" do
    let!(:inventory_item) do
      InventoryItem.create!(
        sku: "TEST-GRPC-001",
        location: "warehouse-1",
        quantity_on_hand: 100,
        quantity_reserved: 0
      )
    end

    it "adjusts stock levels" do
      request = Inventory::V1::AdjustStockRequest.new(
        listing_id: "TEST-GRPC",
        warehouse_id: "warehouse-1",
        quantity_delta: 50,
        reason: "Stock receipt"
      )

      response = stub.adjust_stock(request)

      expect(response).to be_a(Inventory::V1::AdjustStockResponse)
      expect(response.stock.quantity).to eq(150)
      expect(response.stock.sku).to eq("TEST-GRPC-001")
      expect(response.movement).to be_present
      expect(response.movement.quantity).to eq(50)
    end

    it "prevents reducing stock below reserved quantity" do
      inventory_item.update!(quantity_reserved: 50)

      request = Inventory::V1::AdjustStockRequest.new(
        listing_id: "TEST-GRPC",
        warehouse_id: "warehouse-1",
        quantity_delta: -75,
        reason: "Damage"
      )

      expect {
        stub.adjust_stock(request)
      }.to raise_error(GRPC::FailedPrecondition)
    end
  end

  describe "ReserveStock" do
    let!(:inventory_item) do
      InventoryItem.create!(
        sku: "TEST-RESERVE-001",
        location: "default",
        quantity_on_hand: 100,
        quantity_reserved: 0
      )
    end

    it "reserves stock for an order" do
      request = Inventory::V1::ReserveStockRequest.new(
        order_id: "ORDER-123",
        items: [
          Inventory::V1::ReservationItem.new(
            listing_id: "TEST-RESERVE-001",
            quantity: 10
          )
        ],
        expiration_seconds: 3600
      )

      response = stub.reserve_stock(request)

      expect(response.fully_reserved).to be true
      expect(response.reservations.length).to eq(1)

      reservation = response.reservations.first
      expect(reservation.order_id).to eq("ORDER-123")
      expect(reservation.quantity).to eq(10)
      expect(reservation.status).to eq(
        Inventory::V1::ReservationStatus::RESERVATION_STATUS_PENDING
      )

      # Verify database state
      inventory_item.reload
      expect(inventory_item.quantity_reserved).to eq(10)
    end

    it "returns failure when insufficient stock" do
      request = Inventory::V1::ReserveStockRequest.new(
        order_id: "ORDER-456",
        items: [
          Inventory::V1::ReservationItem.new(
            listing_id: "TEST-RESERVE-001",
            quantity: 150
          )
        ]
      )

      response = stub.reserve_stock(request)

      expect(response.fully_reserved).to be false
      expect(response.failures.length).to eq(1)

      failure = response.failures.first
      expect(failure.requested).to eq(150)
      expect(failure.available).to eq(100)
    end
  end

  describe "GetStockBySku" do
    let!(:inventory_item) do
      InventoryItem.create!(
        sku: "TEST-GET-001",
        location: "default",
        quantity_on_hand: 75,
        quantity_reserved: 25
      )
    end

    it "retrieves stock information" do
      request = Inventory::V1::GetStockBySkuRequest.new(
        sku: "TEST-GET-001",
        warehouse_id: "default"
      )

      response = stub.get_stock_by_sku(request)

      expect(response.stock.sku).to eq("TEST-GET-001")
      expect(response.stock.quantity).to eq(75)
      expect(response.stock.reserved).to eq(25)
      expect(response.stock.available).to eq(50)
      expect(response.stock.in_stock).to be true
    end

    it "raises NotFound for non-existent SKU" do
      request = Inventory::V1::GetStockBySkuRequest.new(
        sku: "NONEXISTENT",
        warehouse_id: "default"
      )

      expect {
        stub.get_stock_by_sku(request)
      }.to raise_error(GRPC::NotFound)
    end
  end
end
