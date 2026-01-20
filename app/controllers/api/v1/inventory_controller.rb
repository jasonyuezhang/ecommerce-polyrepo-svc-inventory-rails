# frozen_string_literal: true

module Api
  module V1
    class InventoryController < ApplicationController
      before_action :set_inventory_item, only: [:show, :update, :destroy, :adjust, :reserve, :release, :commit, :movements]

      # GET /api/v1/inventory
      def index
        @items = InventoryItem.all

        # Filters
        @items = @items.by_sku(params[:sku]) if params[:sku].present?
        @items = @items.by_location(params[:location]) if params[:location].present?
        @items = @items.in_stock if params[:in_stock] == "true"
        @items = @items.low_stock if params[:low_stock] == "true"
        @items = @items.out_of_stock if params[:out_of_stock] == "true"

        # Pagination
        @items = @items.page(params[:page]).per(params[:per_page] || 25)

        response.headers["X-Total-Count"] = @items.total_count.to_s
        response.headers["X-Page"] = @items.current_page.to_s
        response.headers["X-Per-Page"] = @items.limit_value.to_s

        render json: {
          data: @items.map { |item| serialize_inventory_item(item) },
          meta: {
            total_count: @items.total_count,
            page: @items.current_page,
            per_page: @items.limit_value,
            total_pages: @items.total_pages
          }
        }
      end

      # GET /api/v1/inventory/:sku
      def show
        render json: { data: serialize_inventory_item(@inventory_item) }
      end

      # POST /api/v1/inventory
      def create
        @inventory_item = InventoryItem.new(inventory_item_params)

        if @inventory_item.save
          render json: { data: serialize_inventory_item(@inventory_item) }, status: :created
        else
          render json: {
            error: "validation_error",
            message: "Failed to create inventory item",
            details: @inventory_item.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/inventory/:sku
      def update
        if @inventory_item.update(inventory_item_update_params)
          render json: { data: serialize_inventory_item(@inventory_item) }
        else
          render json: {
            error: "validation_error",
            message: "Failed to update inventory item",
            details: @inventory_item.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/inventory/:sku
      def destroy
        @inventory_item.destroy
        head :no_content
      end

      # POST /api/v1/inventory/:sku/adjust
      def adjust
        result = InventoryService.adjust_stock(
          @inventory_item,
          quantity: params.require(:quantity).to_i,
          reason: params[:reason],
          reference_type: params[:reference_type],
          reference_id: params[:reference_id],
          metadata: params[:metadata]&.permit!&.to_h || {}
        )

        render json: {
          data: serialize_inventory_item(result[:item]),
          movement: result[:movement].as_json
        }
      end

      # POST /api/v1/inventory/:sku/reserve
      def reserve
        result = InventoryService.reserve_stock(
          @inventory_item,
          quantity: params.require(:quantity).to_i,
          reference_type: params[:reference_type],
          reference_id: params[:reference_id],
          metadata: params[:metadata]&.permit!&.to_h || {}
        )

        render json: {
          data: serialize_inventory_item(result[:item]),
          movement: result[:movement].as_json,
          reservation_id: result[:reservation_id]
        }
      end

      # POST /api/v1/inventory/:sku/release
      def release
        result = InventoryService.release_reservation(
          @inventory_item,
          quantity: params.require(:quantity).to_i,
          reference_type: params[:reference_type],
          reference_id: params[:reference_id],
          metadata: params[:metadata]&.permit!&.to_h || {}
        )

        render json: {
          data: serialize_inventory_item(result[:item]),
          movement: result[:movement].as_json
        }
      end

      # POST /api/v1/inventory/:sku/commit
      def commit
        result = InventoryService.commit_reservation(
          @inventory_item,
          quantity: params.require(:quantity).to_i,
          reference_type: params[:reference_type],
          reference_id: params[:reference_id],
          metadata: params[:metadata]&.permit!&.to_h || {}
        )

        render json: {
          data: serialize_inventory_item(result[:item]),
          movement: result[:movement].as_json
        }
      end

      # GET /api/v1/inventory/:sku/movements
      def movements
        @movements = @inventory_item.stock_movements.recent

        # Filters
        @movements = @movements.by_type(params[:type]) if params[:type].present?
        @movements = @movements.in_period(params[:start_date], params[:end_date]) if params[:start_date].present?

        # Pagination
        @movements = @movements.page(params[:page]).per(params[:per_page] || 50)

        render json: {
          data: @movements.as_json,
          meta: {
            total_count: @movements.total_count,
            page: @movements.current_page,
            per_page: @movements.limit_value
          }
        }
      end

      # GET /api/v1/inventory/low_stock
      def low_stock
        @items = InventoryItem.low_stock.page(params[:page]).per(params[:per_page] || 25)

        render json: {
          data: @items.map { |item| serialize_inventory_item(item) },
          meta: {
            total_count: @items.total_count,
            page: @items.current_page
          }
        }
      end

      # GET /api/v1/inventory/locations
      def locations
        locations = InventoryItem.distinct.pluck(:location)
        render json: { data: locations }
      end

      # POST /api/v1/inventory/bulk_adjust
      def bulk_adjust
        results = []
        errors = []

        params.require(:adjustments).each do |adjustment|
          begin
            item = InventoryItem.find_by!(sku: adjustment[:sku], location: adjustment[:location] || "default")
            result = InventoryService.adjust_stock(
              item,
              quantity: adjustment[:quantity].to_i,
              reason: adjustment[:reason],
              metadata: { bulk_adjustment: true }
            )
            results << { sku: adjustment[:sku], success: true, item: serialize_inventory_item(result[:item]) }
          rescue StandardError => e
            errors << { sku: adjustment[:sku], success: false, error: e.message }
          end
        end

        render json: {
          data: results,
          errors: errors,
          meta: {
            total: results.size + errors.size,
            successful: results.size,
            failed: errors.size
          }
        }
      end

      private

      def set_inventory_item
        @inventory_item = InventoryItem.find_by!(
          sku: params[:sku],
          location: params[:location] || "default"
        )
      end

      def inventory_item_params
        params.require(:inventory_item).permit(
          :sku,
          :location,
          :quantity_on_hand,
          :reorder_point,
          :reorder_quantity,
          :backorderable,
          metadata: {}
        )
      end

      def inventory_item_update_params
        params.require(:inventory_item).permit(
          :reorder_point,
          :reorder_quantity,
          :backorderable,
          metadata: {}
        )
      end

      def serialize_inventory_item(item)
        {
          id: item.id,
          sku: item.sku,
          location: item.location,
          quantity_on_hand: item.quantity_on_hand,
          quantity_reserved: item.quantity_reserved,
          quantity_available: item.quantity_available,
          reorder_point: item.reorder_point,
          reorder_quantity: item.reorder_quantity,
          backorderable: item.backorderable,
          in_stock: item.in_stock?,
          low_stock: item.low_stock?,
          metadata: item.metadata,
          created_at: item.created_at.iso8601,
          updated_at: item.updated_at.iso8601
        }
      end
    end
  end
end
