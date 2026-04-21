require "../../engines/swift_engine"

module Analyzer::Swift
  class Vapor < SwiftEngine
    # Maximum number of lines to look ahead for function parameters
    LOOKAHEAD_LIMIT = 20

    # Patterns for route definitions in Vapor:
    # app.get("path") { ... }
    # app.post("path", "segment") { ... }
    # routes.get("path", ":param") { ... }
    ROUTE_PATTERN = /(\w+)\.(get|post|put|delete|patch)\(([^)]+)\)/

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)

      lines.each_with_index do |line, index|
        next unless route_definition_line?(line)
        match = line.match(ROUTE_PATTERN)
        next unless match

        begin
          method = match[2].upcase
          route_args = match[3]
          route_path = parse_route_path(route_args)

          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(route_path, method, details)

          extract_path_params(route_path, endpoint)
          extract_function_params(lines, index + 1, endpoint)

          endpoints << endpoint
        rescue e
          logger.debug "Error processing endpoint: #{e.message}"
        end
      end

      endpoints
    end

    # Parse route path from route arguments
    # Examples:
    # "hello" -> /hello
    # "users", ":id" -> /users/:id
    # "api", "users", ":userID" -> /api/users/:userID
    def parse_route_path(route_args : String) : String
      # Remove whitespace and split by comma
      segments = route_args.split(',').map(&.strip)

      # Extract quoted strings only (path segments)
      path_segments = [] of String
      segments.each do |seg|
        # Match quoted strings
        if match = seg.match(/^["']([^"']+)["']/)
          path_segments << match[1]
        end
      end

      # Build the path
      if path_segments.empty?
        return "/"
      end

      path = "/" + path_segments.join("/")
      path
    end

    # Extract path parameters from the route pattern (e.g., :id, :userID)
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Extract parameters from function body
    def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      in_function = false
      brace_count = 0
      seen_opening_brace = false

      existing_path_params = Set(String).new
      endpoint.params.each do |p|
        existing_path_params.add(p.name) if p.param_type == "path"
      end

      (start_index...[start_index + LOOKAHEAD_LIMIT, lines.size].min).each do |i|
        line = lines[i]

        if line.includes?(" in ")
          in_function = true
        end

        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        # Extract query parameters from req.query
        if line.includes?("req.query[") || line.includes?("req.query.get(")
          match = line.match(/req\.query\[["']([^"']+)["']\]/) ||
                  line.match(/req\.query\.get\(["']([^"']+)["']\)/)
          if match
            query_name = match[1]
            endpoint.push_param(Param.new(query_name, "", "query"))
          end
        end

        # Extract body parameters from req.content.decode
        if line.includes?("req.content.decode(") || line.includes?("try req.content.decode")
          endpoint.push_param(Param.new("body", "", "json"))
        end

        # Extract headers from req.headers
        if line.includes?("req.headers[")
          match = line.match(/req\.headers\[["']([^"']+)["']\]/)
          if match
            header_name = match[1]
            endpoint.push_param(Param.new(header_name, "", "header"))
          end
        end

        # Extract cookies from req.cookies
        if line.includes?("req.cookies[")
          match = line.match(/req\.cookies\[["']([^"']+)["']\]/)
          if match
            cookie_name = match[1]
            endpoint.push_param(Param.new(cookie_name, "", "cookie"))
          end
        end

        # Extract path parameters from req.parameters.get
        if line.includes?("req.parameters.get(")
          match = line.match(/req\.parameters\.get\(["']([^"']+)["']\)/)
          if match
            param_name = match[1]
            if !existing_path_params.includes?(param_name)
              endpoint.push_param(Param.new(param_name, "", "path"))
              existing_path_params.add(param_name)
            end
          end
        end

        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        if i > start_index && route_definition?(line)
          break
        end
      end
    end

    # Check if a line contains a route definition
    private def route_definition?(line : String) : Bool
      line.includes?(".get(") || line.includes?(".post(") ||
        line.includes?(".put(") || line.includes?(".delete(") ||
        line.includes?(".patch(")
    end

    # Check if a line is a route definition but not a parameter access
    private def route_definition_line?(line : String) : Bool
      route_definition?(line) &&
        !line.includes?("req.parameters") &&
        !line.includes?("req.query")
    end
  end
end
