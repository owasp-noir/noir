require "../../../models/analyzer"

module Analyzer::Rust
  class Rocket < Analyzer
    # Maximum lines to scan ahead for function body analysis
    MAX_FUNCTION_SCAN_LINES = 30

    def analyze
      # Source Analysis
      # Enhanced pattern to capture path, query parameters, and data parameters
      pattern = /#\[(get|post|delete|put|patch)\("([^"]+)"(?:, data = "<([^>]+)>")?\)\]/
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

                  if File.exists?(path) && File.extname(path) == ".rs"
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    lines.each_with_index do |line, index|
                      if line.includes?("#[") && line.includes?(")]")
                        match = line.match(pattern)
                        if match
                          begin
                            callback_argument = match[1]
                            route_argument = match[2]
                            data_argument = match[3]?

                            # Extract parameters from the route
                            params = extract_params(route_argument, data_argument)

                            details = Details.new(PathInfo.new(path, index + 1))
                            endpoint = Endpoint.new("#{route_argument}", callback_to_method(callback_argument), params, details)

                            # Look ahead to extract cookies and headers from function signature/body
                            extract_function_params(lines, index + 1, endpoint)

                            result << endpoint
                          rescue
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

    def callback_to_method(str)
      method = str.split("(").first
      if !method.in?(%w[get post put patch delete])
        method = "get"
      end

      method.upcase
    end

    private def extract_params(route : String, data_param : String?) : Array(Param)
      params = [] of Param

      # Extract path parameters from route (e.g., /users/<id> or /posts/<category>/<id>)
      route.scan(/<(\w+)>/) do |match|
        if match.size > 1
          param_name = match[1]
          params << Param.new(param_name, "", "path") unless param_exists?(params, param_name, "path")
        end
      end

      # Split route by '?' to separate path and query
      parts = route.split("?")

      # Extract query parameters (e.g., ?<query>&<limit>)
      if parts.size > 1
        query_string = parts[1]
        query_string.scan(/<(\w+)>/) do |match|
          if match.size > 1
            param_name = match[1]
            params << Param.new(param_name, "", "query") unless param_exists?(params, param_name, "query")
          end
        end
      end

      # Extract body/data parameter if present
      if data_param && !data_param.empty?
        params << Param.new(data_param, "", "body")
      end

      params
    end

    private def param_exists?(params : Array(Param), name : String, param_type : String) : Bool
      params.any? { |p| p.name == name && p.param_type == param_type }
    end

    # Extract parameters from function signature and body (cookies, headers)
    private def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      in_function = false
      brace_count = 0
      seen_opening_brace = false
      has_cookie_jar = false

      (start_index...[start_index + MAX_FUNCTION_SCAN_LINES, lines.size].min).each do |i|
        line = lines[i]

        # Track if we're inside the function
        if line.includes?("fn ")
          in_function = true
        end

        # Track braces to know when function ends
        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        # Check if this function has CookieJar parameter
        if line.includes?("CookieJar") || line.includes?("&CookieJar")
          has_cookie_jar = true
        end

        # Extract cookies.get("name") or cookies.get_private("name") from within the function
        # Only extract if we've seen CookieJar in this function
        if has_cookie_jar && (line.includes?(".get(\"") || line.includes?(".get_private(\""))
          line.scan(/\.get(?:_private)?\("([^"]+)"\)/) do |cookie_match|
            if cookie_match.size > 1
              cookie_name = cookie_match[1]
              unless endpoint.params.any? { |p| p.name == cookie_name && p.param_type == "cookie" }
                endpoint.push_param(Param.new(cookie_name, "", "cookie"))
              end
            end
          end
        end

        # Extract headers from request.headers().get() pattern
        if line.includes?(".headers().get(")
          match = line.match(/\.headers\(\)\.get\((?:HeaderName::from_static\()?"([^"]+)"/)
          if match
            header_name = match[1]
            unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
          end
        end

        # Stop if we've moved past the function
        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        # Also stop if we hit another route attribute
        if i > start_index && (line.strip.starts_with?("#[get") || line.strip.starts_with?("#[post") ||
           line.strip.starts_with?("#[put") || line.strip.starts_with?("#[delete") ||
           line.strip.starts_with?("#[patch"))
          break
        end
      end
    end
  end
end
