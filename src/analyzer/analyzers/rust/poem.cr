require "../../engines/rust_engine"

module Analyzer::Rust
  class Poem < RustEngine
    HTTP_METHODS = %w[get post put delete patch head options]

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = read_file_content(path).lines
      include_callee = any_to_bool(@options["include_callee"]?)

      # Strategy 1: Parse Route::new().at("/path", get(handler).post(...)) chains
      parse_at_routes(lines, path, endpoints, include_callee)

      # Strategy 2: Parse #[oai(path = "...", method = "...")] poem-openapi attributes
      parse_oai_attributes(lines, path, endpoints, include_callee)

      endpoints
    end

    def parse_at_routes(lines : Array(String), path : String, endpoints : Array(Endpoint), include_callee : Bool)
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
          attach_handler_callees(lines, handler_name, path, endpoint) if include_callee

          endpoints << endpoint
        end
      end
    end

    def parse_oai_attributes(lines : Array(String), path : String, endpoints : Array(Endpoint), include_callee : Bool)
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
        attach_next_function_callees(lines, index + 1, path, endpoint) if include_callee

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
      function_index = find_handler_function_index(lines, handler_name)
      scan_function(lines, function_index, endpoint) if function_index
    end

    # Walks a function starting at start_index: first extracts typed/destructured
    # extractors from the signature, then scans the body for header/cookie access.
    def scan_function(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      function_index = find_next_function_index(lines, start_index)
      return unless function_index

      in_signature = true
      brace_count = 0
      seen_opening_brace = false

      (function_index...[function_index + 40, lines.size].min).each do |i|
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

        if seen_opening_brace && brace_count == 0 && i > function_index
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

    private def attach_handler_callees(lines : Array(String), handler_name : String, path : String, endpoint : Endpoint)
      function_index = find_handler_function_index(lines, handler_name)
      attach_function_callees(lines, function_index, path, endpoint) if function_index
    end

    private def attach_next_function_callees(lines : Array(String), start_index : Int32, path : String, endpoint : Endpoint)
      function_index = find_next_function_index(lines, start_index)
      attach_function_callees(lines, function_index, path, endpoint) if function_index
    end

    private def attach_function_callees(lines : Array(String), function_index : Int32, path : String, endpoint : Endpoint)
      function_body = extract_rust_function_body(lines, function_index)
      return unless function_body

      body, body_start_line = function_body
      callees = Noir::RustCalleeExtractor.callees_for_body(body, path, body_start_line)
      attach_rust_callees(endpoint, callees)
    end

    private def find_handler_function_index(lines : Array(String), handler_name : String) : Int32?
      local_name = handler_name.split("::").last
      lines.each_with_index do |line, index|
        stripped = Noir::RustCalleeExtractor.strip_comment(line).strip
        return index if stripped.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+#{local_name}\b/)
      end
    end

    private def find_next_function_index(lines : Array(String), start_index : Int32) : Int32?
      (start_index...[start_index + 40, lines.size].min).each do |index|
        stripped = Noir::RustCalleeExtractor.strip_comment(lines[index]).strip
        return index if stripped.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+[A-Za-z_]\w*\b/)
      end
    end
  end
end
