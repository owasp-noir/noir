require "../../engines/rust_engine"

module Analyzer::Rust
  class Axum < RustEngine
    ROUTE_PATTERN = /\.route\("([^"]+)",\s*([^)]+)\)/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = read_file_content(path).lines
      include_callee = any_to_bool(@options["include_callee"]?)
      functions = include_callee ? collect_function_callees(lines, path) : Hash(String, Array(Noir::RustCalleeExtractor::Entry)).new

      lines.each_with_index do |line, index|
        next unless line.includes? ".route("
        match = line.match(ROUTE_PATTERN)
        next unless match

        begin
          route_argument = match[1]
          callback_argument = match[2]
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(route_argument, callback_to_method(callback_argument), details)
          attach_route_callees(endpoint, callback_argument, functions) if include_callee
          endpoints << endpoint
        rescue
        end
      end

      endpoints
    end

    private def collect_function_callees(lines : Array(String), path : String) : Hash(String, Array(Noir::RustCalleeExtractor::Entry))
      functions = Hash(String, Array(Noir::RustCalleeExtractor::Entry)).new

      lines.each_with_index do |line, index|
        stripped = Noir::RustCalleeExtractor.strip_comment(line).strip
        if match = stripped.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_]\w*)\b/)
          function_body = extract_rust_function_body(lines, index)
          if function_body
            body, body_start_line = function_body
            functions[match[1]] = Noir::RustCalleeExtractor.callees_for_body(body, path, body_start_line)
          end
        end
      end

      functions
    end

    private def attach_route_callees(endpoint : Endpoint,
                                     callback_argument : String,
                                     functions : Hash(String, Array(Noir::RustCalleeExtractor::Entry)))
      handler = extract_route_handler(callback_argument)
      return unless handler

      if callees = functions[handler]?
        attach_rust_callees(endpoint, callees)
      end
    end

    private def extract_route_handler(callback_argument : String) : String?
      if match = callback_argument.match(/\b(?:get|post|put|delete|patch|head|options)\s*\(\s*([A-Za-z_]\w*)/)
        match[1]
      end
    end

    def callback_to_method(str)
      method = str.split("(").first.strip
      if !method.in?(%w[get post put delete])
        method = "get"
      end

      method.upcase
    end
  end
end
