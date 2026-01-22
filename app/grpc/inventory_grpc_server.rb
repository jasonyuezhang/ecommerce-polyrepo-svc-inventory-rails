#!/usr/bin/env ruby
# frozen_string_literal: true

# gRPC Server for Inventory Service
# Production-ready gRPC server using proto-generated stubs

require "grpc"

# Load proto-generated files if available
begin
  require_relative "../../lib/proto/inventory/v1/inventory_pb"
  require_relative "../../lib/proto/inventory/v1/inventory_services_pb"
  PROTO_AVAILABLE = true
rescue LoadError
  PROTO_AVAILABLE = false
  Rails.logger.warn("Proto files not generated. Run: rake grpc:generate")
end

module InventoryGrpc
  # gRPC Service Implementation
  class InventoryServiceImpl < Inventory::V1::InventoryService::Service
    # GetStock retrieves stock information by SKU
    def get_stock_by_sku(request, _call)
      item = InventoryItem.find_by!(sku: request.sku, location: request.warehouse_id.presence || "default")

      Inventory::V1::GetStockBySkuResponse.new(
        stock: build_stock_level(item)
      )
    rescue ActiveRecord::RecordNotFound => e
      raise GRPC::NotFound.new("Stock not found for SKU: #{request.sku}")
    rescue StandardError => e
      Rails.logger.error("gRPC get_stock_by_sku error: #{e.message}")
      raise GRPC::Internal.new("Internal error")
    end

    # AdjustStock adjusts stock by a delta amount
    def adjust_stock(request, _call)
      item = find_or_create_inventory_item(
        request.listing_id,
        request.variant_id,
        request.warehouse_id
      )

      result = InventoryService.adjust_stock(
        item,
        quantity: request.quantity_delta,
        reason: request.reason,
        reference_type: "grpc_request",
        reference_id: request.reference_id
      )

      Inventory::V1::AdjustStockResponse.new(
        stock: build_stock_level(result[:item]),
        movement: build_stock_movement(result[:movement])
      )
    rescue InventoryItem::InsufficientStockError => e
      raise GRPC::FailedPrecondition.new(e.message)
    rescue StandardError => e
      Rails.logger.error("gRPC adjust_stock error: #{e.message}")
      raise GRPC::Internal.new("Internal error")
    end

    # ReserveStock reserves stock for an order
    def reserve_stock(request, _call)
      reservations = []
      failures = []

      request.items.each do |item_request|
        begin
          item = find_or_create_inventory_item(
            item_request.listing_id,
            item_request.variant_id,
            request.preferred_warehouse_id
          )

          result = InventoryService.reserve_stock(
            item,
            quantity: item_request.quantity,
            reference_type: "order",
            reference_id: request.order_id,
            metadata: { order_id: request.order_id }
          )

          reservations << build_reservation(
            result[:reservation_id],
            request.order_id,
            item_request,
            item
          )
        rescue InventoryItem::InsufficientStockError => e
          failures << Inventory::V1::ReservationFailure.new(
            listing_id: item_request.listing_id,
            variant_id: item_request.variant_id,
            requested: item_request.quantity,
            available: item&.quantity_available || 0,
            reason: e.message
          )
        end
      end

      Inventory::V1::ReserveStockResponse.new(
        reservations: reservations,
        fully_reserved: failures.empty?,
        failures: failures
      )
    rescue StandardError => e
      Rails.logger.error("gRPC reserve_stock error: #{e.message}")
      raise GRPC::Internal.new("Internal error")
    end

    # ReleaseReservation releases a stock reservation
    def release_reservation(request, _call)
      # In a real implementation, you would track reservations in a separate table
      # For now, we'll use the movement metadata to find the original reservation

      movement = StockMovement.find_by!(
        reference_type: "order",
        metadata: { reservation_id: request.reservation_id }
      )

      item = movement.inventory_item
      quantity = movement.quantity.abs

      result = InventoryService.release_reservation(
        item,
        quantity: quantity,
        reference_type: "order",
        reference_id: movement.reference_id,
        metadata: {
          reservation_id: request.reservation_id,
          reason: request.reason
        }
      )

      reservation = build_reservation_from_movement(movement, item)
      reservation.status = Inventory::V1::ReservationStatus::RESERVATION_STATUS_RELEASED

      Inventory::V1::ReleaseReservationResponse.new(
        reservation: reservation
      )
    rescue ActiveRecord::RecordNotFound
      raise GRPC::NotFound.new("Reservation not found: #{request.reservation_id}")
    rescue InventoryItem::InsufficientReservationError => e
      raise GRPC::FailedPrecondition.new(e.message)
    rescue StandardError => e
      Rails.logger.error("gRPC release_reservation error: #{e.message}")
      raise GRPC::Internal.new("Internal error")
    end

    # ConfirmReservation confirms a reservation (deducts from stock)
    def confirm_reservation(request, _call)
      movement = StockMovement.find_by!(
        reference_type: "order",
        metadata: { reservation_id: request.reservation_id }
      )

      item = movement.inventory_item
      quantity = movement.quantity.abs

      result = InventoryService.commit_reservation(
        item,
        quantity: quantity,
        reference_type: "order",
        reference_id: movement.reference_id,
        metadata: { reservation_id: request.reservation_id }
      )

      reservation = build_reservation_from_movement(movement, item)
      reservation.status = Inventory::V1::ReservationStatus::RESERVATION_STATUS_CONFIRMED

      Inventory::V1::ConfirmReservationResponse.new(
        reservation: reservation,
        movement: build_stock_movement(result[:movement])
      )
    rescue ActiveRecord::RecordNotFound
      raise GRPC::NotFound.new("Reservation not found: #{request.reservation_id}")
    rescue InventoryItem::InsufficientReservationError => e
      raise GRPC::FailedPrecondition.new(e.message)
    rescue StandardError => e
      Rails.logger.error("gRPC confirm_reservation error: #{e.message}")
      raise GRPC::Internal.new("Internal error")
    end

    # HealthCheck returns service health status
    def health_check(_request, _call)
      # Check database connection
      ActiveRecord::Base.connection.execute("SELECT 1")

      Common::V1::HealthCheckResponse.new(
        status: Common::V1::HealthStatus::HEALTH_STATUS_HEALTHY,
        message: "Inventory service is healthy",
        timestamp: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i)
      )
    rescue StandardError => e
      Rails.logger.error("Health check failed: #{e.message}")
      Common::V1::HealthCheckResponse.new(
        status: Common::V1::HealthStatus::HEALTH_STATUS_UNHEALTHY,
        message: "Database connection failed: #{e.message}",
        timestamp: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i)
      )
    end

    private

    def find_or_create_inventory_item(listing_id, variant_id, warehouse_id)
      sku = variant_id.present? ? "#{listing_id}-#{variant_id}" : listing_id
      location = warehouse_id.presence || "default"

      InventoryItem.find_or_create_by!(sku: sku, location: location) do |item|
        item.quantity_on_hand = 0
        item.quantity_reserved = 0
      end
    end

    def build_stock_level(item)
      Inventory::V1::StockLevel.new(
        listing_id: extract_listing_id(item.sku),
        variant_id: extract_variant_id(item.sku),
        sku: item.sku,
        warehouse_id: item.location,
        quantity: item.quantity_on_hand,
        reserved: item.quantity_reserved,
        available: item.quantity_available,
        in_stock: item.in_stock?,
        status: stock_status(item),
        updated_at: Google::Protobuf::Timestamp.new(
          seconds: item.updated_at.to_i,
          nanos: item.updated_at.nsec
        )
      )
    end

    def build_stock_movement(movement)
      Inventory::V1::StockMovement.new(
        id: movement.id.to_s,
        listing_id: extract_listing_id(movement.inventory_item.sku),
        variant_id: extract_variant_id(movement.inventory_item.sku),
        sku: movement.inventory_item.sku,
        warehouse_id: movement.inventory_item.location,
        type: movement_type_to_proto(movement.movement_type),
        quantity: movement.quantity,
        quantity_before: movement.quantity_before,
        quantity_after: movement.quantity_after,
        reference_id: movement.reference_id.to_s,
        reference_type: movement.reference_type,
        reason: movement.reason,
        created_at: Google::Protobuf::Timestamp.new(
          seconds: movement.created_at.to_i,
          nanos: movement.created_at.nsec
        )
      )
    end

    def build_reservation(reservation_id, order_id, item_request, inventory_item)
      Inventory::V1::Reservation.new(
        id: reservation_id,
        order_id: order_id,
        listing_id: item_request.listing_id,
        variant_id: item_request.variant_id,
        sku: inventory_item.sku,
        warehouse_id: inventory_item.location,
        quantity: item_request.quantity,
        status: Inventory::V1::ReservationStatus::RESERVATION_STATUS_PENDING,
        created_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i)
      )
    end

    def build_reservation_from_movement(movement, inventory_item)
      Inventory::V1::Reservation.new(
        id: movement.metadata["reservation_id"],
        order_id: movement.reference_id,
        sku: inventory_item.sku,
        warehouse_id: inventory_item.location,
        quantity: movement.quantity.abs,
        created_at: Google::Protobuf::Timestamp.new(
          seconds: movement.created_at.to_i,
          nanos: movement.created_at.nsec
        )
      )
    end

    def stock_status(item)
      if item.out_of_stock?
        Inventory::V1::StockStatus::STOCK_STATUS_OUT_OF_STOCK
      elsif item.low_stock?
        Inventory::V1::StockStatus::STOCK_STATUS_LOW_STOCK
      else
        Inventory::V1::StockStatus::STOCK_STATUS_IN_STOCK
      end
    end

    def movement_type_to_proto(movement_type)
      case movement_type
      when "receipt" then Inventory::V1::MovementType::MOVEMENT_TYPE_RECEIVED
      when "sale", "commit" then Inventory::V1::MovementType::MOVEMENT_TYPE_SOLD
      when "return" then Inventory::V1::MovementType::MOVEMENT_TYPE_RETURNED
      when "transfer_out" then Inventory::V1::MovementType::MOVEMENT_TYPE_TRANSFER_OUT
      when "transfer_in" then Inventory::V1::MovementType::MOVEMENT_TYPE_TRANSFER_IN
      when "adjustment", "count_adjustment" then Inventory::V1::MovementType::MOVEMENT_TYPE_ADJUSTMENT
      when "reservation" then Inventory::V1::MovementType::MOVEMENT_TYPE_RESERVED
      when "release" then Inventory::V1::MovementType::MOVEMENT_TYPE_UNRESERVED
      else Inventory::V1::MovementType::MOVEMENT_TYPE_UNSPECIFIED
      end
    end

    def extract_listing_id(sku)
      sku.split("-").first
    end

    def extract_variant_id(sku)
      parts = sku.split("-")
      parts.length > 1 ? parts[1..-1].join("-") : ""
    end
  end
end

# Server runner
class InventoryGrpcServer
  def initialize(port: nil)
    @port = port || ENV.fetch("GRPC_PORT", "50051")
    @server = GRPC::RpcServer.new(
      pool_size: ENV.fetch("GRPC_POOL_SIZE", 30).to_i,
      poll_period: 1,
      max_send_message_length: -1,
      max_receive_message_length: -1
    )
  end

  def start
    unless PROTO_AVAILABLE
      puts "ERROR: Proto files not generated. Run: rake grpc:generate"
      exit 1
    end

    @server.add_http2_port("0.0.0.0:#{@port}", :this_port_is_insecure)
    @server.handle(InventoryGrpc::InventoryServiceImpl.new)

    Rails.logger.info("Inventory gRPC server starting on port #{@port}")
    puts "🚀 Inventory gRPC server listening on 0.0.0.0:#{@port}"
    STDOUT.flush

    # Handle graceful shutdown
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\n⏹️  Shutting down gRPC server..."
        STDOUT.flush
        @server.stop
      end
    end

    # Run server (blocks)
    @server.run_till_terminated
  rescue StandardError => e
    Rails.logger.error("gRPC server error: #{e.message}\n#{e.backtrace.join("\n")}")
    puts "❌ gRPC server error: #{e.message}"
    STDOUT.flush
    exit 1
  end
end

# Run the server if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  require_relative "../../config/environment"
  InventoryGrpcServer.new.start
end
