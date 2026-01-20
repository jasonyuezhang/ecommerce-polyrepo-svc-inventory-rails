#!/usr/bin/env ruby
# frozen_string_literal: true

# gRPC Server for Inventory Service
# Provides a high-performance interface for inter-service communication.
#
# Usage:
#   ruby app/grpc/inventory_server.rb
#   GRPC_PORT=50052 ruby app/grpc/inventory_server.rb
#

require_relative "../../config/environment"
require "grpc"

module Inventory
  module V1
    # Request/Response message classes
    # In production, these would be generated from .proto files

    class GetStockRequest
      attr_accessor :sku, :location

      def initialize(sku: "", location: "default")
        @sku = sku
        @location = location
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(sku: json["sku"], location: json["location"])
      end

      def self.encode(instance)
        JSON.generate({sku: instance.sku, location: instance.location})
      end
    end

    class StockResponse
      attr_accessor :sku, :location, :quantity_on_hand, :quantity_reserved,
                    :quantity_available, :in_stock, :backorderable, :success, :error

      def initialize(attrs = {})
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({
          sku: instance.sku, location: instance.location, quantity_on_hand: instance.quantity_on_hand,
          quantity_reserved: instance.quantity_reserved, quantity_available: instance.quantity_available,
          in_stock: instance.in_stock, backorderable: instance.backorderable, success: instance.success, error: instance.error
        }.compact)
      end
    end

    class AdjustStockRequest
      attr_accessor :sku, :location, :quantity, :reason, :reference_type, :reference_id

      def initialize(attrs = {})
        @location = "default"
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({
          sku: instance.sku, location: instance.location, quantity: instance.quantity,
          reason: instance.reason, reference_type: instance.reference_type, reference_id: instance.reference_id
        }.compact)
      end
    end

    class ReserveStockRequest
      attr_accessor :sku, :location, :quantity, :reference_type, :reference_id

      def initialize(attrs = {})
        @location = "default"
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({sku: instance.sku, location: instance.location, quantity: instance.quantity,
                      reference_type: instance.reference_type, reference_id: instance.reference_id}.compact)
      end
    end

    class ReservationResponse
      attr_accessor :sku, :location, :quantity_reserved, :reservation_id,
                    :quantity_available, :success, :error

      def initialize(attrs = {})
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({sku: instance.sku, location: instance.location, quantity_reserved: instance.quantity_reserved,
                      reservation_id: instance.reservation_id, quantity_available: instance.quantity_available,
                      success: instance.success, error: instance.error}.compact)
      end
    end

    class ReleaseRequest
      attr_accessor :sku, :location, :quantity, :reservation_id, :reference_type, :reference_id

      def initialize(attrs = {})
        @location = "default"
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({sku: instance.sku, location: instance.location, quantity: instance.quantity, reservation_id: instance.reservation_id,
                      reference_type: instance.reference_type, reference_id: instance.reference_id}.compact)
      end
    end

    class CommitRequest
      attr_accessor :sku, :location, :quantity, :reservation_id, :reference_type, :reference_id

      def initialize(attrs = {})
        @location = "default"
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({sku: instance.sku, location: instance.location, quantity: instance.quantity, reservation_id: instance.reservation_id,
                      reference_type: instance.reference_type, reference_id: instance.reference_id}.compact)
      end
    end

    class CheckAvailabilityRequest
      attr_accessor :sku, :location, :quantity

      def initialize(attrs = {})
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({sku: instance.sku, location: instance.location, quantity: instance.quantity}.compact)
      end
    end

    class AvailabilityResponse
      attr_accessor :sku, :requested_quantity, :total_available,
                    :is_available, :backorderable, :success, :error

      def initialize(attrs = {})
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({sku: instance.sku, requested_quantity: instance.requested_quantity, total_available: instance.total_available,
                      is_available: instance.is_available, backorderable: instance.backorderable,
                      success: instance.success, error: instance.error}.compact)
      end
    end

    class BulkCheckRequest
      attr_accessor :items

      def initialize(items: [])
        @items = items
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(items: json["items"] || [])
      end

      def self.encode(instance)
        JSON.generate({items: instance.items})
      end
    end

    class BulkCheckResponse
      attr_accessor :results, :all_available, :success, :error

      def initialize(attrs = {})
        attrs.each { |k, v| send("#{k}=", v) if respond_to?("#{k}=") }
      end

      def self.decode(data)
        json = JSON.parse(data)
        new(json.transform_keys(&:to_sym))
      end

      def self.encode(instance)
        JSON.generate({results: instance.results, all_available: instance.all_available,
                      success: instance.success, error: instance.error}.compact)
      end
    end

    # gRPC Service Implementation
    class InventoryServiceHandler
      include GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = "inventory.v1.InventoryService"

      # Define RPC methods
      rpc :GetStock, GetStockRequest, StockResponse
      rpc :AdjustStock, AdjustStockRequest, StockResponse
      rpc :ReserveStock, ReserveStockRequest, ReservationResponse
      rpc :ReleaseReservation, ReleaseRequest, StockResponse
      rpc :CommitReservation, CommitRequest, StockResponse
      rpc :CheckAvailability, CheckAvailabilityRequest, AvailabilityResponse
      rpc :BulkCheckAvailability, BulkCheckRequest, BulkCheckResponse

      def get_stock(request, _call)
        item = find_inventory_item(request.sku, request.location)

        StockResponse.new(
          sku: item.sku,
          location: item.location,
          quantity_on_hand: item.quantity_on_hand,
          quantity_reserved: item.quantity_reserved,
          quantity_available: item.quantity_available,
          in_stock: item.in_stock?,
          backorderable: item.backorderable?,
          success: true
        )
      rescue ActiveRecord::RecordNotFound => e
        StockResponse.new(success: false, error: "Item not found: #{e.message}")
      rescue StandardError => e
        Rails.logger.error("gRPC get_stock error: #{e.message}")
        StockResponse.new(success: false, error: "Internal error")
      end

      def adjust_stock(request, _call)
        item = find_inventory_item(request.sku, request.location)

        result = InventoryService.adjust_stock(
          item,
          quantity: request.quantity,
          reason: request.reason,
          reference_type: request.reference_type,
          reference_id: request.reference_id
        )

        item = result[:item]
        StockResponse.new(
          sku: item.sku,
          location: item.location,
          quantity_on_hand: item.quantity_on_hand,
          quantity_reserved: item.quantity_reserved,
          quantity_available: item.quantity_available,
          in_stock: item.in_stock?,
          backorderable: item.backorderable?,
          success: true
        )
      rescue ActiveRecord::RecordNotFound => e
        StockResponse.new(success: false, error: "Item not found: #{e.message}")
      rescue InventoryItem::InsufficientStockError => e
        StockResponse.new(success: false, error: e.message)
      rescue StandardError => e
        Rails.logger.error("gRPC adjust_stock error: #{e.message}")
        StockResponse.new(success: false, error: "Internal error")
      end

      def reserve_stock(request, _call)
        item = find_inventory_item(request.sku, request.location)

        result = InventoryService.reserve_stock(
          item,
          quantity: request.quantity,
          reference_type: request.reference_type,
          reference_id: request.reference_id
        )

        item = result[:item]
        ReservationResponse.new(
          sku: item.sku,
          location: item.location,
          quantity_reserved: request.quantity,
          reservation_id: result[:reservation_id],
          quantity_available: item.quantity_available,
          success: true
        )
      rescue ActiveRecord::RecordNotFound => e
        ReservationResponse.new(success: false, error: "Item not found: #{e.message}")
      rescue InventoryItem::InsufficientStockError => e
        ReservationResponse.new(success: false, error: e.message)
      rescue StandardError => e
        Rails.logger.error("gRPC reserve_stock error: #{e.message}")
        ReservationResponse.new(success: false, error: "Internal error")
      end

      def release_reservation(request, _call)
        item = find_inventory_item(request.sku, request.location)

        result = InventoryService.release_reservation(
          item,
          quantity: request.quantity,
          reference_type: request.reference_type,
          reference_id: request.reference_id
        )

        item = result[:item]
        StockResponse.new(
          sku: item.sku,
          location: item.location,
          quantity_on_hand: item.quantity_on_hand,
          quantity_reserved: item.quantity_reserved,
          quantity_available: item.quantity_available,
          in_stock: item.in_stock?,
          backorderable: item.backorderable?,
          success: true
        )
      rescue ActiveRecord::RecordNotFound => e
        StockResponse.new(success: false, error: "Item not found: #{e.message}")
      rescue InventoryItem::InsufficientReservationError => e
        StockResponse.new(success: false, error: e.message)
      rescue StandardError => e
        Rails.logger.error("gRPC release_reservation error: #{e.message}")
        StockResponse.new(success: false, error: "Internal error")
      end

      def commit_reservation(request, _call)
        item = find_inventory_item(request.sku, request.location)

        result = InventoryService.commit_reservation(
          item,
          quantity: request.quantity,
          reference_type: request.reference_type,
          reference_id: request.reference_id
        )

        item = result[:item]
        StockResponse.new(
          sku: item.sku,
          location: item.location,
          quantity_on_hand: item.quantity_on_hand,
          quantity_reserved: item.quantity_reserved,
          quantity_available: item.quantity_available,
          in_stock: item.in_stock?,
          backorderable: item.backorderable?,
          success: true
        )
      rescue ActiveRecord::RecordNotFound => e
        StockResponse.new(success: false, error: "Item not found: #{e.message}")
      rescue InventoryItem::InsufficientReservationError => e
        StockResponse.new(success: false, error: e.message)
      rescue StandardError => e
        Rails.logger.error("gRPC commit_reservation error: #{e.message}")
        StockResponse.new(success: false, error: "Internal error")
      end

      def check_availability(request, _call)
        result = InventoryService.check_availability(
          request.sku,
          quantity: request.quantity,
          location: request.location.presence
        )

        AvailabilityResponse.new(
          sku: result[:sku],
          requested_quantity: result[:requested_quantity],
          total_available: result[:total_available],
          is_available: result[:is_available],
          backorderable: result[:backorderable],
          success: true
        )
      rescue StandardError => e
        Rails.logger.error("gRPC check_availability error: #{e.message}")
        AvailabilityResponse.new(success: false, error: "Internal error")
      end

      def bulk_check_availability(request, _call)
        items = request.items.map do |item|
          { sku: item.sku, quantity: item.quantity, location: item.location }
        end

        results = InventoryService.check_bulk_availability(items)
        all_available = results.all? { |r| r[:is_available] }

        BulkCheckResponse.new(
          results: results,
          all_available: all_available,
          success: true
        )
      rescue StandardError => e
        Rails.logger.error("gRPC bulk_check_availability error: #{e.message}")
        BulkCheckResponse.new(success: false, error: "Internal error")
      end

      private

      def find_inventory_item(sku, location)
        InventoryItem.find_by!(sku: sku, location: location.presence || "default")
      end
    end

    # gRPC Service Definition
    # In production, this would be generated from .proto files
    class Service
      include GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = "inventory.v1.InventoryService"

      # Define RPC methods
      # Note: Using JSON serialization as a workaround until proper .proto files are created
      rpc :GetStock, GetStockRequest, StockResponse
      rpc :AdjustStock, AdjustStockRequest, StockResponse
      rpc :ReserveStock, ReserveStockRequest, ReservationResponse
      rpc :ReleaseReservation, ReleaseRequest, StockResponse
      rpc :CommitReservation, CommitRequest, StockResponse
      rpc :CheckAvailability, CheckAvailabilityRequest, AvailabilityResponse
      rpc :BulkCheckAvailability, BulkCheckRequest, BulkCheckResponse
    end
  end
end

# Server runner
class InventoryGrpcServer
  def initialize(port: nil)
    @port = port || ENV.fetch("GRPC_PORT", "50051")
    @server = GRPC::RpcServer.new(
      pool_size: ENV.fetch("GRPC_POOL_SIZE", 30).to_i,
      poll_period: 1
    )
  end

  def start
    @server.add_http2_port("0.0.0.0:#{@port}", :this_port_is_insecure)
    @server.handle(Inventory::V1::InventoryServiceHandler.new)

    Rails.logger.info("Inventory gRPC server starting on port #{@port}")
    puts "Inventory gRPC server listening on 0.0.0.0:#{@port}"
    STDOUT.flush

    # Start server in a thread to avoid blocking
    server_thread = Thread.new do
      begin
        @server.run
      rescue => e
        Rails.logger.error("gRPC server error: #{e.message}")
        puts "gRPC server error: #{e.message}"
        STDOUT.flush
      end
    end

    # Handle graceful shutdown
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        puts "\nShutting down gRPC server..."
        STDOUT.flush
        @server.stop
        server_thread.join(5) # Wait up to 5 seconds for graceful shutdown
      end
    end

    # Keep the main thread alive
    server_thread.join
  end
end

# Run the server if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  InventoryGrpcServer.new.start
end
