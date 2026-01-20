# frozen_string_literal: true

class HealthController < ApplicationController
  # GET /health
  def show
    render json: {
      status: "healthy",
      service: "inventory",
      version: "1.0.0",
      timestamp: Time.current.iso8601
    }
  end

  # GET /health/ready
  def ready
    checks = {
      database: database_connected?,
      redis: redis_connected?
    }

    all_healthy = checks.values.all?

    render json: {
      status: all_healthy ? "ready" : "not_ready",
      checks: checks,
      timestamp: Time.current.iso8601
    }, status: all_healthy ? :ok : :service_unavailable
  end

  # GET /health/live
  def live
    render json: {
      status: "alive",
      timestamp: Time.current.iso8601
    }
  end

  private

  def database_connected?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end

  def redis_connected?
    return true unless defined?(Redis)

    Redis.current.ping == "PONG"
  rescue StandardError
    false
  end
end
