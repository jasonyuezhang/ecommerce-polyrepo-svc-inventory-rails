require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"

Bundler.require(*Rails.groups)

module SvcInventoryRails
  class Application < Rails::Application
    config.load_defaults 7.1

    # API-only mode
    config.api_only = true

    # Eager loading configuration
    config.eager_load = Rails.env.production?

    # Disable host authorization for Kubernetes environment
    config.hosts.clear

    # Autoload paths
    config.autoload_paths += %W[
      #{config.root}/app/services
      #{config.root}/app/grpc
    ]

    # Time zone
    config.time_zone = "UTC"

    # Active Record
    config.active_record.default_timezone = :utc
    config.active_record.schema_format = :sql

    # Generators
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
      g.test_framework :rspec
      g.fixture_replacement :factory_bot, dir: "spec/factories"
    end

    # CORS configuration
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins "*"
        resource "*",
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options, :head],
          expose: ["X-Total-Count", "X-Page", "X-Per-Page"]
      end
    end

    # Active Job
    config.active_job.queue_adapter = :sidekiq

    # Logging
    if Rails.env.production?
      config.lograge.enabled = true
      config.lograge.formatter = Lograge::Formatters::Json.new
      config.lograge.custom_options = lambda do |event|
        {
          time: Time.current.iso8601,
          request_id: event.payload[:request_id],
          remote_ip: event.payload[:remote_ip]
        }
      end
    end

    # Exception handling
    config.action_dispatch.rescue_responses.merge!(
      "ActiveRecord::RecordNotFound" => :not_found,
      "ActiveRecord::RecordInvalid" => :unprocessable_entity,
      "ActionController::ParameterMissing" => :bad_request
    )
  end
end
