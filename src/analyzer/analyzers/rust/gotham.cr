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
      function_bodies = collect_function_bodies(lines)

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
            if function_body = function_bodies[handler_name]?
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

    private def collect_function_bodies(lines : Array(String)) : Hash(String, Tuple(String, Int32))
      function_bodies = {} of String => Tuple(String, Int32)
      in_block_comment = false
      index = 0

      while index < lines.size
        stripped, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(lines[index], in_block_comment)
        match = stripped.strip.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_]\w*)\b/)

        if match
          function_body = extract_rust_function_body_with_end(lines, index)
          if function_body
            body, body_start_line, end_index = function_body
            function_bodies[match[1]] = {body, body_start_line}
            index = end_index
            in_block_comment = false
          end
        end

        index += 1
      end

      function_bodies
    end

    # Extract cookies and headers from the handler function body
    private def extract_handler_params(body : String, endpoint : Endpoint)
      in_block_comment = false

      body.each_line do |raw_line|
        line, in_block_comment = strip_comments_preserving_strings(raw_line, in_block_comment)

        # Extract cookies from .cookie() or cookies().get() patterns
        if line.includes?(".cookie(")
          match = line.match(/\.cookie\s*\(\s*"([^"]+)"\s*\)/)
          if match
            cookie_name = match[1]
            unless endpoint.params.any? { |p| p.name == cookie_name && p.param_type == "cookie" }
              endpoint.push_param(Param.new(cookie_name, "", "cookie"))
            end
          end
        end

        # Extract headers from .headers().get() or HeaderMap access
        if line.includes?(".headers()") && line.includes?(".get(")
          match = line.match(/\.headers\(\)\s*\.get\s*\(\s*"([^"]+)"\s*\)/)
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

    private def strip_comments_preserving_strings(line : String, in_block_comment : Bool) : Tuple(String, Bool)
      in_string = false
      escaped = false
      index = 0
      stripped = String::Builder.new

      while index < line.size
        char = line[index]

        if in_block_comment
          if char == '*' && line[index + 1]? == '/'
            in_block_comment = false
            index += 1
          end
        elsif in_string
          stripped << char
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '"'
            in_string = false
          end
        elsif char == '"'
          in_string = true
          stripped << char
        elsif char == '/' && line[index + 1]? == '/'
          return {stripped.to_s, in_block_comment}
        elsif char == '/' && line[index + 1]? == '*'
          in_block_comment = true
          index += 1
        else
          stripped << char
        end

        index += 1
      end

      {stripped.to_s, in_block_comment}
    end
  end
end
