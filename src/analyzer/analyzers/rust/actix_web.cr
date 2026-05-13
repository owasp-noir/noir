require "../../engines/rust_engine"

module Analyzer::Rust
  class ActixWeb < RustEngine
    ROUTE_PATTERN            = /#\[(get|post|put|delete|patch)\("([^"]+)"\)\]/
    FUNCTION_LOOKAHEAD_LINES = 20

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = read_file_content(path).lines
      include_callee = any_to_bool(@options["include_callee"]?)

      lines.each_with_index do |line, index|
        next unless line.to_s.includes? "#["
        match = line.match(ROUTE_PATTERN)
        next unless match

        begin
          route_argument = match[2]
          callback_argument = match[1]
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(route_argument, callback_to_method(callback_argument), details)

          extract_path_params(route_argument, endpoint)
          extract_function_params(lines, index + 1, endpoint)
          attach_handler_callees(lines, index + 1, path, endpoint) if include_callee

          endpoints << endpoint
        rescue e
          logger.debug "Error processing endpoint: #{e.message}"
        end
      end

      endpoints
    end

    def callback_to_method(str)
      method = str.split("(").first
      if !method.in?(%w[get post put delete patch])
        method = "get"
      end

      method.upcase
    end

    private def attach_handler_callees(lines : Array(String), start_index : Int32, path : String, endpoint : Endpoint)
      function_index = find_next_function_index(lines, start_index)
      return unless function_index

      function_body = extract_rust_function_body(lines, function_index)
      return unless function_body

      body, body_start_line = function_body
      callees = Noir::RustCalleeExtractor.callees_for_body(body, path, body_start_line)
      attach_rust_callees(endpoint, callees)
    end

    private def find_next_function_index(lines : Array(String), start_index : Int32) : Int32?
      (start_index...[start_index + FUNCTION_LOOKAHEAD_LINES, lines.size].min).each do |index|
        stripped = Noir::RustCalleeExtractor.strip_comment(lines[index]).strip
        return index if stripped.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+[A-Za-z_]\w*\b/)
      end
    end

    # Extract path parameters from the route pattern like /users/{id}
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/\{(\w+)\}/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Extract parameters from function signature and body
    def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      # Look ahead up to 20 lines for the function definition and body
      in_function = false
      brace_count = 0
      seen_opening_brace = false

      (start_index...[start_index + FUNCTION_LOOKAHEAD_LINES, lines.size].min).each do |i|
        line = lines[i]

        # Track if we're inside the function
        if line.includes?("async fn ") || line.includes?("fn ")
          in_function = true
        end

        # Track braces to know when function ends
        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        # Extract query parameters from web::Query<T>
        if line.includes?("web::Query<") || line.includes?(": web::Query")
          endpoint.push_param(Param.new("query", "", "query"))
        end

        # Extract JSON body from web::Json<T>
        if line.includes?("web::Json<") || line.includes?(": web::Json")
          endpoint.push_param(Param.new("body", "", "json"))
        end

        # Extract form body from web::Form<T>
        if line.includes?("web::Form<") || line.includes?(": web::Form")
          endpoint.push_param(Param.new("form", "", "form"))
        end

        # Extract headers from .headers().get()
        if line.includes?(".headers().get(")
          match = line.match(/\.headers\(\)\.get\("([^"]+)"\)/)
          if match
            header_name = match[1]
            endpoint.push_param(Param.new(header_name, "", "header"))
          end
        end

        # Extract cookies from .cookie()
        if line.includes?(".cookie(")
          match = line.match(/\.cookie\("([^"]+)"\)/)
          if match
            cookie_name = match[1]
            endpoint.push_param(Param.new(cookie_name, "", "cookie"))
          end
        end

        # Stop if we've moved past the function (brace count is back to 0 after we've seen an opening brace)
        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end
      end
    end
  end
end
