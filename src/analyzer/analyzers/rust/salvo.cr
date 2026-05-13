require "../../engines/rust_engine"

module Analyzer::Rust
  class Salvo < RustEngine
    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = read_file_content(path).lines
      include_callee = any_to_bool(@options["include_callee"]?)

      # Strategy 1: Parse Router chain patterns
      # e.g., Router::with_path("users/<id>").get(get_user)
      # e.g., Router::new().push(Router::with_path("items").get(list_items))
      parse_router_chains(lines, path, endpoints, include_callee)

      # Strategy 2: Parse #[endpoint] macro patterns
      # e.g., #[endpoint(method = Get, path = "/api/users")]
      parse_endpoint_macros(lines, path, endpoints, include_callee)

      endpoints
    end

    def parse_router_chains(lines : Array(String), path : String, endpoints : Array(Endpoint), include_callee : Bool)
      lines.each_with_index do |line, index|
        # Match Router::with_path("...").method(handler) or .path("...").method(handler)
        # Pattern: with_path("path") followed by .method(handler)
        if line.includes?("with_path(") || line.includes?(".path(")
          # Extract path from with_path("...") or .path("...")
          path_match = line.match(/(?:with_path|\.path)\s*\(\s*"([^"]+)"\s*\)/)
          if path_match
            route_path = path_match[1]

            # Look for HTTP method in same line or nearby lines
            search_range = [index, [index + 3, lines.size - 1].min]
            (search_range[0]..search_range[1]).each do |i|
              method_match = lines[i].match(/\.(get|post|put|delete|patch|head|options)\s*\(/)
              if method_match
                method = method_match[1].upcase
                details = Details.new(PathInfo.new(path, index + 1))
                endpoint = Endpoint.new("/#{route_path.lstrip('/')}", method, details)

                # Extract path parameters like <id>
                extract_path_params(route_path, endpoint)

                # Look for handler function and extract params
                handler_match = lines[i].match(/\.(get|post|put|delete|patch|head|options)\s*\(\s*(\w+)/)
                if handler_match
                  handler_name = handler_match[2]
                  extract_handler_params(lines, handler_name, endpoint)
                  attach_handler_callees(lines, handler_name, path, endpoint) if include_callee
                end

                endpoints << endpoint
                break
              end
            end
          end
        end
      end
    end

    def parse_endpoint_macros(lines : Array(String), path : String, endpoints : Array(Endpoint), include_callee : Bool)
      lines.each_with_index do |line, index|
        # Match #[endpoint(method = Get, path = "/path")]
        if line.strip.starts_with?("#[endpoint(")
          method = "GET"
          route_path = "/"

          method_match = line.match(/method\s*=\s*(\w+)/)
          if method_match
            method = method_match[1].upcase
          end

          path_match = line.match(/path\s*=\s*"([^"]+)"/)
          if path_match
            route_path = path_match[1]
          end

          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(route_path, method, details)

          extract_path_params(route_path, endpoint)
          extract_function_params(lines, index + 1, endpoint)
          attach_next_function_callees(lines, index + 1, path, endpoint) if include_callee

          endpoints << endpoint
        end
      end
    end

    # Extract path parameters from the route pattern like /users/<id>
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/<(\w+)>/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Look for handler function definition and extract params from its signature/body
    def extract_handler_params(lines : Array(String), handler_name : String, endpoint : Endpoint)
      function_index = find_handler_function_index(lines, handler_name)
      extract_function_params(lines, function_index, endpoint) if function_index
    end

    # Extract parameters from function signature and body
    def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      function_index = find_next_function_index(lines, start_index)
      return unless function_index

      brace_count = 0
      seen_opening_brace = false

      (function_index...[function_index + 30, lines.size].min).each do |i|
        line = lines[i]

        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        # Extract query parameters from QueryParam or req.query
        if line.includes?("QueryParam") || line.includes?("req.query")
          endpoint.push_param(Param.new("query", "", "query"))
        end

        # Extract JSON body from JsonBody
        if line.includes?("JsonBody")
          endpoint.push_param(Param.new("body", "", "json"))
        end

        # Extract form body from FormBody
        if line.includes?("FormBody")
          endpoint.push_param(Param.new("form", "", "form"))
        end

        # Extract headers from req.header/req.headers
        if line.includes?("req.header(") || line.includes?("req.headers().get(")
          match = line.match(/req\.header(?:s\(\)\.get)?\s*\(\s*"([^"]+)"\s*\)/)
          if match
            header_name = match[1]
            endpoint.push_param(Param.new(header_name, "", "header"))
          end
        end

        # Extract cookies from req.cookie
        if line.includes?("req.cookie(")
          match = line.match(/req\.cookie\s*\(\s*"([^"]+)"\s*\)/)
          if match
            cookie_name = match[1]
            endpoint.push_param(Param.new(cookie_name, "", "cookie"))
          end
        end

        if seen_opening_brace && brace_count == 0 && i > function_index
          break
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
      lines.each_with_index do |line, index|
        stripped = Noir::RustCalleeExtractor.strip_comment(line).strip
        return index if stripped.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+#{handler_name}\b/)
      end
    end

    private def find_next_function_index(lines : Array(String), start_index : Int32) : Int32?
      (start_index...[start_index + 30, lines.size].min).each do |index|
        stripped = Noir::RustCalleeExtractor.strip_comment(lines[index]).strip
        return index if stripped.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+[A-Za-z_]\w*\b/)
      end
    end
  end
end
