# frozen_string_literal: true

namespace :grpc do
  desc "Generate Ruby code from proto files"
  task :generate do
    require "fileutils"

    proto_dir = File.expand_path("../../../proto-schemas/proto", __dir__)
    output_dir = File.expand_path("../../../svc-inventory-rails/lib/proto", __dir__)

    FileUtils.mkdir_p(output_dir)

    puts "Generating Ruby gRPC stubs from proto files..."
    puts "Proto dir: #{proto_dir}"
    puts "Output dir: #{output_dir}"

    # Generate from inventory.proto
    inventory_proto = File.join(proto_dir, "inventory/v1/inventory.proto")
    common_proto = File.join(proto_dir, "common/v1/common.proto")

    if File.exist?(inventory_proto)
      cmd = [
        "grpc_tools_ruby_protoc",
        "-I", proto_dir,
        "--ruby_out=#{output_dir}",
        "--grpc_out=#{output_dir}",
        inventory_proto
      ].join(" ")

      puts "Running: #{cmd}"
      system(cmd) || raise("Failed to generate proto files")

      # Also generate common.proto if it exists
      if File.exist?(common_proto)
        cmd = [
          "grpc_tools_ruby_protoc",
          "-I", proto_dir,
          "--ruby_out=#{output_dir}",
          "--grpc_out=#{output_dir}",
          common_proto
        ].join(" ")

        puts "Running: #{cmd}"
        system(cmd)
      end

      puts "Successfully generated gRPC stubs in #{output_dir}"
    else
      puts "Warning: Proto file not found at #{inventory_proto}"
      puts "Run this task after proto-schemas submodule is available"
    end
  end

  desc "Start gRPC server"
  task :server do
    require_relative "../../config/environment"
    require_relative "../../app/grpc/inventory_grpc_server"

    InventoryGrpcServer.new.start
  end
end
