require "../../engines/rust_engine"

module Analyzer::Rust
  class Poem < RustEngine
    HTTP_METHODS = %w[get post put delete patch head options]

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)

      # Strategy 1: Parse Route::new().at("/path", get(handler).post(...)) chains
      parse_at_routes(lines, path, endpoints)

      # Strategy 2: Parse #[oai(path = "...", method = "...")] poem-openapi attributes
      parse_oai_attributes(lines, path, endpoints)

      endpoints
    end

    def parse_at_routes(lines : Array(String), path : String, endpoints : Array(Endpoint))
      lines.each_with_index do |line, index|
        next unless line.includes?(".at(")

        path_match = line.match(/\.at\s*\(\s*"([^"]+)"\s*,\s*(.+)$/)
        next unless path_match

        route_path = path_match[1]
        remainder = path_match[2]

        methods_and_handlers = [] of Tuple(String, String)
        remainder.scan(/\b(get|post|put|delete|patch|head|options)\s*\(\s*([\w:]+)/) do |m|
          methods_and_handlers << {m[1].upcase, m[2]}
        end

        next if methods_and_handlers.empty?

        methods_and_handlers.each do |method, handler_name|
          details = Details.new(PathInfo.new(path, index + 1))
          normalized_path = normalize_path(route_path)
          endpoint = Endpoint.new(normalized_path, method, details)

          extract_path_params(route_path, endpoint)
          extract_handler_params(lines, handler_name, endpoint)

          endpoints << endpoint
        end
      end
    end

    def parse_oai_attributes(lines : Array(String), path : String, endpoints : Array(Endpoint))
      lines.each_with_index do |line, index|
        stripped = line.strip
        next unless stripped.starts_with?("#[oai(")

        path_match = line.match(/path\s*=\s*"([^"]+)"/)
        method_match = line.match(/method\s*=\s*"([^"]+)"/)
        next unless path_match && method_match

        route_path = path_match[1]
        method = method_match[1].upcase

        details = Details.new(PathInfo.new(path, index + 1))
        normalized_path = normalize_path(route_path)
        endpoint = Endpoint.new(normalized_path, method, details)

        extract_path_params(route_path, endpoint)
        scan_function(lines, index + 1, endpoint)

        endpoints << endpoint
      end
    end

    # Convert Poem's :param syntax to {param} for output consistency
    def normalize_path(route : String) : String
      result = route.gsub(/:(\w+)/) { "{#{$~[1]}}" }
      result.starts_with?("/") ? result : "/#{result}"
    end

    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    def extract_handler_params(lines : Array(String), handler_name : String, endpoint : Endpoint)
      lines.each_with_index do |line, index|
        if line.includes?("fn #{handler_name}")
          scan_function(lines, index, endpoint)
          break
        end
      end
    end

    # Walks a function starting at start_index: first extracts typed/destructured
    # extractors from the signature, then scans the body for header/cookie access.
    def scan_function(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      in_signature = true
      brace_count = 0
      seen_opening_brace = false

      (start_index...[start_index + 40, lines.size].min).each do |i|
        line = lines[i]

        if in_signature
          extract_signature_params(line, endpoint)
        end

        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
          in_signature = false
        end
        brace_count -= line.count('}')

        unless in_signature
          extract_body_params(line, endpoint)
        end

        if seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        if i > start_index && line.strip.starts_with?("#[")
          break
        end
      end
    end

    def extract_signature_params(line : String, endpoint : Endpoint)
      if line.match(/Query\s*\(\s*[^)]+\s*\)/) || line.includes?(": Query<")
        endpoint.push_param(Param.new("query", "", "query"))
      end

      if line.match(/Json\s*\(\s*[^)]+\s*\)/) || line.includes?(": Json<")
        endpoint.push_param(Param.new("body", "", "json"))
      end

      if line.match(/Form\s*\(\s*[^)]+\s*\)/) || line.includes?(": Form<")
        endpoint.push_param(Param.new("form", "", "form"))
      end
    end

    def extract_body_params(line : String, endpoint : Endpoint)
      if line.includes?("req.header(") || line.includes?(".header(")
        match = line.match(/\.header\s*\(\s*"([^"]+)"\s*\)/)
        if match
          endpoint.push_param(Param.new(match[1], "", "header"))
        end
      end

      if line.includes?(".cookie")
        match = line.match(/\.cookie\s*\(\s*\)\s*\.\s*get\s*\(\s*"([^"]+)"\s*\)/)
        match ||= line.match(/\.cookie\s*\(\s*"([^"]+)"\s*\)/)
        if match
          endpoint.push_param(Param.new(match[1], "", "cookie"))
        end
      end
    end
  end
end
