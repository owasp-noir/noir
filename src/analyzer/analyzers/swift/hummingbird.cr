require "../../../models/analyzer"

module Analyzer::Swift
  class Hummingbird < Analyzer
    # Maximum number of lines to look ahead for function parameters
    LOOKAHEAD_LIMIT = 20

    def analyze
      # Source Analysis
      # Patterns for route definitions in Hummingbird:
      # router.get("path") { ... }
      # router.post("path") { ... }
      # Route pattern should have router. or any router variable before the method
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
                      if route_definition_line?(line)
                        match = line.match(pattern)
                        if match
                          begin
                            # Extract HTTP method
                            method = match[2].upcase

                            # Extract route arguments
                            route_args = match[3]

                            # Parse route path from arguments
                            route_path = parse_route_path(route_args)

                            details = Details.new(PathInfo.new(path, index + 1))
                            endpoint = Endpoint.new(route_path, method, details)

                            # Extract path parameters from route pattern (e.g., ":id", ":userId")
                            extract_path_params(route_path, endpoint)

                            # Look ahead to extract parameters from function body
                            extract_function_params(lines, index + 1, endpoint)

                            result << endpoint
                          rescue e
                            logger.debug "Error processing endpoint: #{e.message}"
                          end
                        end
                      end
                    end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}, error: #{e}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug "Error in analyze: #{e.message}"
      end

      result
    end

    # Parse route path from route arguments
    # Examples:
    # "hello" -> /hello
    # "users/:id" -> /users/:id
    # "api/users/:userID" -> /api/users/:userID
    def parse_route_path(route_args : String) : String
      # Match the first quoted string (the path)
      if match = route_args.match(/["']([^"']+)["']/)
        path = match[1]
        # Ensure path starts with /
        path = "/" + path unless path.starts_with?("/")
        return path
      end

      # Default to root if no path found
      "/"
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

        # Extract query parameters from request.uri.queryParameters
        if line.includes?("request.uri.queryParameters.get(") ||
           line.includes?("request.uri.queryParameters[")
          match = line.match(/request\.uri\.queryParameters\.get\(["']([^"']+)["']\)/) ||
                  line.match(/request\.uri\.queryParameters\[["']([^"']+)["']\]/)
          if match
            query_name = match[1]
            endpoint.push_param(Param.new(query_name, "", "query"))
          end
        end

        # Extract body parameters from request.decode
        if line.includes?("request.decode(") || line.includes?("await request.decode")
          endpoint.push_param(Param.new("body", "", "json"))
        end

        # Extract headers from request.headers
        if line.includes?("request.headers[")
          match = line.match(/request\.headers\[["']([^"']+)["']\]/)
          if match
            header_name = match[1]
            endpoint.push_param(Param.new(header_name, "", "header"))
          end
        end

        # Extract cookies from request.cookies
        if line.includes?("request.cookies[")
          match = line.match(/request\.cookies\[["']([^"']+)["']\]/)
          if match
            cookie_name = match[1]
            endpoint.push_param(Param.new(cookie_name, "", "cookie"))
          end
        end

        # Extract path parameters from context.parameters.require or context.parameters.get
        if line.includes?("context.parameters.require(") ||
           line.includes?("context.parameters.get(")
          match = line.match(/context\.parameters\.(require|get)\(["']([^"']+)["']\)/)
          if match
            param_name = match[2]
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
        if i > start_index && route_definition?(line)
          break
        end
      end
    end

    # Check if a line contains a route definition
    private def route_definition?(line : String) : Bool
      (line.includes?(".get(") || line.includes?(".post(") ||
        line.includes?(".put(") || line.includes?(".delete(") ||
        line.includes?(".patch("))
    end

    # Check if a line is a route definition but not a parameter access
    private def route_definition_line?(line : String) : Bool
      route_definition?(line) &&
        !line.includes?("context.parameters") &&
        !line.includes?("request.uri.queryParameters")
    end
  end
end
