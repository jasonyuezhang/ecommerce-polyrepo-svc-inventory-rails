# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::MimeResponds

  # Error handling
  rescue_from StandardError, with: :handle_internal_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
  rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  rescue_from InventoryItem::InsufficientStockError, with: :handle_insufficient_stock
  rescue_from InventoryItem::InsufficientReservationError, with: :handle_insufficient_reservation

  private

  def handle_not_found(exception)
    render json: {
      error: "not_found",
      message: exception.message,
      status: 404
    }, status: :not_found
  end

  def handle_validation_error(exception)
    render json: {
      error: "validation_error",
      message: exception.message,
      details: exception.record&.errors&.full_messages,
      status: 422
    }, status: :unprocessable_entity
  end

  def handle_parameter_missing(exception)
    render json: {
      error: "bad_request",
      message: exception.message,
      status: 400
    }, status: :bad_request
  end

  def handle_insufficient_stock(exception)
    render json: {
      error: "insufficient_stock",
      message: exception.message,
      status: 422
    }, status: :unprocessable_entity
  end

  def handle_insufficient_reservation(exception)
    render json: {
      error: "insufficient_reservation",
      message: exception.message,
      status: 422
    }, status: :unprocessable_entity
  end

  def handle_internal_error(exception)
    Rails.logger.error("Internal error: #{exception.message}\n#{exception.backtrace&.first(10)&.join("\n")}")

    render json: {
      error: "internal_server_error",
      message: Rails.env.production? ? "An unexpected error occurred" : exception.message,
      status: 500
    }, status: :internal_server_error
  end
end
