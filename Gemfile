source "https://rubygems.org"

ruby "~> 3.2.0"

# Rails framework
gem "rails", "~> 7.1.0"

# Database
gem "pg", "~> 1.5"

# JSON serialization
gem "jbuilder", "~> 2.11"
gem "oj", "~> 3.16"

# gRPC
gem "grpc", "~> 1.60"
gem "grpc-tools", "~> 1.60"

# Application server
gem "puma", "~> 6.4"

# Environment variables
gem "dotenv-rails", "~> 2.8"

# Background jobs
gem "sidekiq", "~> 7.2"
gem "redis", "~> 5.0"

# API utilities
gem "rack-cors", "~> 2.0"
gem "kaminari", "~> 1.2"

# Monitoring
gem "lograge", "~> 0.14"

# Health checks
gem "rails-healthcheck", "~> 1.4"

group :development, :test do
  gem "debug", "~> 1.9"
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.2"
  gem "rubocop", "~> 1.59"
  gem "rubocop-rails", "~> 2.23"
  gem "rubocop-rspec", "~> 2.25"
end

group :development do
  gem "annotate", "~> 3.2"
  gem "bullet", "~> 7.1"
end

group :test do
  gem "shoulda-matchers", "~> 6.0"
  gem "simplecov", "~> 0.22", require: false
  gem "database_cleaner-active_record", "~> 2.1"
  gem "timecop", "~> 0.9"
end

gem "sqlite3", "~> 2.9"
