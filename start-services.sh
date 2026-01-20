#!/bin/bash

echo "Starting Rails HTTP server..."
./bin/rails server -b 0.0.0.0 2>&1 &
RAILS_PID=$!

echo "Starting gRPC server..."
bundle exec ruby app/grpc/inventory_server.rb 2>&1 &
GRPC_PID=$!

echo "Rails PID: $RAILS_PID, gRPC PID: $GRPC_PID"

# Keep the container running
while true; do
  sleep 10

  # Check if Rails is still running
  if ! kill -0 $RAILS_PID 2>/dev/null; then
    echo "Rails server stopped, restarting..."
    ./bin/rails server -b 0.0.0.0 2>&1 &
    RAILS_PID=$!
  fi

  # Check if gRPC is still running
  if ! kill -0 $GRPC_PID 2>/dev/null; then
    echo "gRPC server stopped, restarting..."
    bundle exec ruby app/grpc/inventory_server.rb 2>&1 &
    GRPC_PID=$!
  fi
done
