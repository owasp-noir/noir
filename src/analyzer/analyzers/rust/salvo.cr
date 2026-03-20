require "../../../models/analyzer"

module Analyzer::Rust
  class Salvo < Analyzer
    def analyze
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

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

                  if File.exists?(path) && File.extname(path) == ".rs"
                    analyze_file(path)
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug "Error during Salvo analysis: #{e.message}"
      end

      result
    end

    def analyze_file(path : String)
      lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)

      # Strategy 1: Parse Router chain patterns
      # e.g., Router::with_path("users/<id>").get(get_user)
      # e.g., Router::new().push(Router::with_path("items").get(list_items))
      parse_router_chains(lines, path)

      # Strategy 2: Parse #[endpoint] macro patterns
      # e.g., #[endpoint(method = Get, path = "/api/users")]
      parse_endpoint_macros(lines, path)
    end

    def parse_router_chains(lines : Array(String), path : String)
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
                end

                result << endpoint
                break
              end
            end
          end
        end
      end
    end

    def parse_endpoint_macros(lines : Array(String), path : String)
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
          endpoint = Endpoint.new("#{route_path}", method, details)

          extract_path_params(route_path, endpoint)
          extract_function_params(lines, index + 1, endpoint)

          result << endpoint
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
      lines.each_with_index do |line, index|
        if line.includes?("fn #{handler_name}")
          extract_function_params(lines, index, endpoint)
          break
        end
      end
    end

    # Extract parameters from function signature and body
    def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      brace_count = 0
      seen_opening_brace = false

      (start_index...[start_index + 30, lines.size].min).each do |i|
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

        if seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        if i > start_index && line.strip.starts_with?("#[")
          break
        end
      end
    end
  end
end
