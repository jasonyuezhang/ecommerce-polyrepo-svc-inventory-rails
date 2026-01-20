# frozen_string_literal: true

# Puma configuration file
# https://puma.io/puma/Puma/DSL.html

# Threads per worker
max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Workers (processes)
# WEB_CONCURRENCY is typically set to the number of CPU cores
workers ENV.fetch("WEB_CONCURRENCY", 2)

# Port
port ENV.fetch("PORT", 3000)

# Environment
environment ENV.fetch("RAILS_ENV", "development")

# Preload app for better memory efficiency with workers
preload_app!

# Allow puma to be restarted by `bin/rails restart` command
plugin :tmp_restart

# Worker boot/shutdown hooks
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Graceful shutdown
on_worker_shutdown do
  # Clean up any resources
end

# Logging
# stdout_redirect '/var/log/puma.stdout.log', '/var/log/puma.stderr.log', true

# PID file
pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")

# State file (for pumactl)
state_path "tmp/pids/puma.state"

# Bind to Unix socket in production (optional)
# bind "unix://#{ENV.fetch('PUMA_SOCKET', 'tmp/sockets/puma.sock')}"

# Health check endpoint
# activate_control_app 'unix://tmp/sockets/pumactl.sock'

# SSL configuration (if needed)
# ssl_bind '0.0.0.0', '9292', {
#   key: 'path/to/key',
#   cert: 'path/to/cert'
# }
