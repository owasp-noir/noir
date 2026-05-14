require "../../engines/rust_engine"

module Analyzer::Rust
  class Gotham < RustEngine
    # Maximum lines to look ahead for handler name
    MAX_HANDLER_LOOKUP_LINES = 5

    # Gotham uses builder pattern: Router::builder().get("/path").to(handler)
    # Route paths must start with /
    ROUTE_PATTERN = /\.(get|post|put|delete|patch|head|options)\s*\(\s*"(\/[^"]*)"\s*\)/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = read_file_content(path).lines
      include_callee = any_to_bool(@options["include_callee"]?)

      lines.each_with_index do |line, index|
        # Look for Gotham routing patterns like .get("/path")
        next unless line.includes?(".") && (line.includes?("get") || line.includes?("post") ||
                    line.includes?("put") || line.includes?("delete") ||
                    line.includes?("patch") || line.includes?("head") ||
                    line.includes?("options"))
        match = line.match(ROUTE_PATTERN)
        next unless match

        begin
          method = match[1]
          route_path = match[2]

          # Parse path parameters (Gotham uses :param syntax)
          params = [] of Param
          final_path = route_path.gsub(/:(\w+)/) do |param_match|
            param_name = param_match[1..-1] # Remove the ':'
            params << Param.new(param_name, "", "path")
            ":#{param_name}"
          end

          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(final_path, method.upcase, details)
          params.each do |param|
            endpoint.push_param(param)
          end

          # Try to find the handler function and extract cookies/headers
          # Look for .to(handler_name) in nearby lines
          handler_name = find_handler_name(lines, index)
          if handler_name
            function_body = find_handler_body(lines, handler_name)
            if function_body
              body, body_start_line = function_body
              extract_handler_params(body, endpoint)
              attach_rust_callees(endpoint, Noir::RustCalleeExtractor.callees_for_body(body, path, body_start_line)) if include_callee
            end
          end

          endpoints << endpoint
        rescue
        end
      end

      endpoints
    end

    # Find the handler function name from .to(handler) pattern
    private def find_handler_name(lines : Array(String), start_index : Int32) : String?
      (start_index...[start_index + MAX_HANDLER_LOOKUP_LINES, lines.size].min).each do |i|
        line = lines[i]
        match = line.match(/\.to\s*\(\s*(?:[A-Za-z_]\w*::)*([A-Za-z_]\w*)\s*\)/)
        if match
          return match[1]
        end
      end
      nil
    end

    private def find_handler_body(lines : Array(String), handler_name : String) : Tuple(String, Int32)?
      function_index = find_handler_function_index(lines, handler_name)
      return unless function_index

      extract_rust_function_body(lines, function_index)
    end

    private def find_handler_function_index(lines : Array(String), handler_name : String) : Int32?
      in_block_comment = false

      lines.each_with_index do |line, index|
        stripped, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(line, in_block_comment)
        match = stripped.strip.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_]\w*)\b/)
        return index if match && match[1] == handler_name
      end
    end

    # Extract cookies and headers from the handler function body
    private def extract_handler_params(body : String, endpoint : Endpoint)
      in_block_comment = false

      body.each_line do |raw_line|
        line, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(raw_line, in_block_comment)

        # Extract cookies from .cookie() or cookies().get() patterns
        if line.includes?(".cookie(")
          match = raw_line.match(/\.cookie\s*\(\s*"([^"]+)"\s*\)/)
          if match
            cookie_name = match[1]
            unless endpoint.params.any? { |p| p.name == cookie_name && p.param_type == "cookie" }
              endpoint.push_param(Param.new(cookie_name, "", "cookie"))
            end
          end
        end

        # Extract headers from .headers().get() or HeaderMap access
        if line.includes?(".headers()") && line.includes?(".get(")
          match = raw_line.match(/\.headers\(\)\s*\.get\s*\(\s*"([^"]+)"\s*\)/)
          if match
            header_name = match[1]
            unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
          end
        end

        # Extract headers using header::XXX patterns (Gotham-style)
        if line.includes?("header::")
          match = line.match(/header::(\w+)/)
          if match
            header_name = match[1].gsub("_", "-")
            unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
          end
        end
      end
    end
  end
end
