require "../../engines/rust_engine"

module Analyzer::Rust
  class Axum < RustEngine
    ROUTE_PATTERN = /\.route\("([^"]+)",\s*([^)]+)\)/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line.with_index do |line, index|
          next unless line.includes? ".route("
          match = line.match(ROUTE_PATTERN)
          next unless match

          begin
            route_argument = match[1]
            callback_argument = match[2]
            details = Details.new(PathInfo.new(path, index + 1))
            endpoints << Endpoint.new(route_argument, callback_to_method(callback_argument), details)
          rescue
          end
        end
      end

      endpoints
    end

    def callback_to_method(str)
      method = str.split("(").first
      if !method.in?(%w[get post put delete])
        method = "get"
      end

      method.upcase
    end
  end
end
