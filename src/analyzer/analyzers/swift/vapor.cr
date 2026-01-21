require "../../../models/analyzer"

module Analyzer::Swift
  class Vapor < Analyzer
    # Maximum number of lines to look ahead for function parameters
    LOOKAHEAD_LIMIT = 20

    def analyze
      # Source Analysis
      # Patterns for route definitions in Vapor:
      # app.get("path") { ... }
      # app.post("path", "segment") { ... }
      # routes.get("path", ":param") { ... }
      # Route pattern should have app. or routes. or any grouped route before the method
      pattern = /(\w+)\.(get|post|put|delete|patch)\(([^)]+)\)/
      channel = Channel(String).new

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)

                  if File.exists?(path) && File.extname(path) == ".swift"
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    lines.each_with_index do |line, index|
                      # Look for route definitions
                      # Check if this is a route definition (has app. or identifier. before the method)
                      # and not a parameter access (req.parameters, req.query)
                      if (line.includes?(".get(") || line.includes?(".post(") ||
                         line.includes?(".put(") || line.includes?(".delete(") ||
                         line.includes?(".patch(")) && !line.includes?("req.parameters") &&
                         !line.includes?("req.query")
                        match = line.match(pattern)
                        if match
                          begin
                            # Extract HTTP method
                            method = match[2].upcase

                            # Extract route arguments (can be multiple path segments)
                            route_args = match[3]

                            # Parse route path from arguments
                            route_path = parse_route_path(route_args)

                            details = Details.new(PathInfo.new(path, index + 1))
                            endpoint = Endpoint.new(route_path, method, details)

                            # Extract path parameters from route pattern (e.g., ":id", ":userID")
                            extract_path_params(route_path, endpoint)

                            # Look ahead to extract parameters from function body
                            extract_function_params(lines, index + 1, endpoint)

                            result << endpoint
                          rescue
                            logger.debug "Error processing endpoint: #{e.message}"
                          end
                        end
                      end
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue
      end

      result
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
      # Look ahead for the function body
      in_function = false
      brace_count = 0
      seen_opening_brace = false

      # Track already-added path parameters to avoid duplicates
      existing_path_params = Set(String).new
      endpoint.params.each do |p|
        existing_path_params.add(p.name) if p.param_type == "path"
      end

      (start_index...[start_index + LOOKAHEAD_LIMIT, lines.size].min).each do |i|
        line = lines[i]

        # Track if we're inside the function
        if line.includes?(" in ")
          in_function = true
        end

        # Track braces to know when function ends
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
            # Only add if not already added from path pattern
            if !existing_path_params.includes?(param_name)
              endpoint.push_param(Param.new(param_name, "", "path"))
              existing_path_params.add(param_name)
            end
          end
        end

        # Stop if we've moved past the function (brace count is back to 0 after we've seen an opening brace)
        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        # Also stop if we hit another route definition
        if i > start_index && (line.includes?(".get(") || line.includes?(".post(") ||
           line.includes?(".put(") || line.includes?(".delete(") || line.includes?(".patch("))
          break
        end
      end
    end
  end
end
