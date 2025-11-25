require "../../../models/analyzer"

module Analyzer::Rust
  class Rwf < Analyzer
    def analyze
      # Source Analysis
      # Look for route! macro calls and Controller implementations
      route_pattern = /route!\("([^"]+)"\s*=>\s*(\w+)\)/
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
                      # Look for route! macro definitions
                      if line.includes? "route!("
                        match = line.match(route_pattern)
                        if match
                          begin
                            route_path = match[1]
                            controller_name = match[2]
                            details = Details.new(PathInfo.new(path, index + 1))
                            
                            # Extract HTTP methods supported by the controller
                            methods = extract_controller_methods(lines, controller_name)
                            
                            # If no specific methods found, default to GET
                            if methods.empty?
                              methods = ["GET"]
                            end
                            
                            # Create an endpoint for each HTTP method
                            methods.each do |http_method|
                              endpoint = Endpoint.new(route_path, http_method, details)
                              
                              # Extract path parameters from route pattern (e.g., /users/:id)
                              extract_path_params(route_path, endpoint)
                              
                              # Look for controller implementation to extract more parameters
                              extract_controller_params(lines, controller_name, endpoint)
                              
                              result << endpoint
                            end
                          rescue
                          end
                        end
                      end
                    end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
      end

      result
    end

    # Extract path parameters from the route pattern like /users/:id
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Extract HTTP methods supported by the controller
    def extract_controller_methods(lines : Array(String), controller_name : String) : Array(String)
      methods = [] of String
      in_controller = false
      in_handle_method = false
      brace_count = 0
      seen_opening_brace = false

      lines.each_with_index do |line, _|
        # Check if we're entering the controller definition
        if line.includes?("struct #{controller_name}")
          in_controller = true
        end

        # Track if we're in the handle method
        if in_controller && (line.includes?("async fn handle") || line.includes?("fn handle"))
          in_handle_method = true
        end

        # Track braces to know when method ends
        if in_handle_method
          brace_count += line.count('{')
          if brace_count > 0
            seen_opening_brace = true
          end
          brace_count -= line.count('}')

          # Look for match request.method() pattern to detect supported methods
          if line.includes?("match request.method()")
            # Continue reading to find Method::GET, Method::POST, etc.
            next
          end

          # Extract HTTP methods from Method::GET, Method::POST, etc.
          if line.includes?("Method::")
            ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"].each do |method|
              if line.includes?("Method::#{method}")
                methods << method unless methods.includes?(method)
              end
            end
          end

          # Stop if we've moved past the method
          if seen_opening_brace && brace_count == 0
            in_handle_method = false
            in_controller = false
            break
          end
        end

        # Stop looking if we hit another struct definition
        if in_controller && line.strip.starts_with?("struct ") && !line.includes?(controller_name)
          in_controller = false
          break
        end
      end

      methods
    end

    # Extract parameters from controller implementation
    def extract_controller_params(lines : Array(String), controller_name : String, endpoint : Endpoint)
      # Find the controller struct and its handle method
      in_controller = false
      in_handle_method = false
      brace_count = 0
      seen_opening_brace = false
      # Track path parameters already added from route to avoid duplicates
      existing_path_params = endpoint.params.select { |p| p.param_type == "path" }.map(&.name).to_set

      lines.each_with_index do |line, _|
        # Check if we're entering the controller definition
        if line.includes?("struct #{controller_name}")
          in_controller = true
        end

        # Track if we're in the handle method
        if in_controller && (line.includes?("async fn handle") || line.includes?("fn handle"))
          in_handle_method = true
        end

        # Track braces to know when method ends
        if in_handle_method
          brace_count += line.count('{')
          if brace_count > 0
            seen_opening_brace = true
          end
          brace_count -= line.count('}')

          # Extract path parameters from request.path_parameter with or without type
          # Supports: request.path_parameter("id"), request.path_parameter::<i64>("id")
          if line.includes?("request.path_parameter")
            extract_typed_params(line, /request\.path_parameter/, endpoint, "path", existing_path_params)
          end

          # Extract query parameters from request.query_parameter()
          if line.includes?("request.query_parameter")
            extract_typed_params(line, /request\.query_parameter/, endpoint, "query")
          end

          # Extract body/JSON parameters from request.body()
          if line.includes?("request.body()")
            endpoint.push_param(Param.new("body", "", "json"))
          end

          # Extract form data from request.form_data()
          if line.includes?("request.form_data()")
            endpoint.push_param(Param.new("form", "", "form"))
          end

          # Extract headers from request.header()
          if line.includes?("request.header(")
            line.scan(/request\.header\("([^"]+)"\)/) do |match|
              header_name = match[1]
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
          end

          # Extract cookies from request.cookie()
          if line.includes?("request.cookie(")
            line.scan(/request\.cookie\("([^"]+)"\)/) do |match|
              cookie_name = match[1]
              endpoint.push_param(Param.new(cookie_name, "", "cookie"))
            end
          end

          # Stop if we've moved past the method (brace count is back to 0 after we've seen an opening brace)
          if seen_opening_brace && brace_count == 0
            in_handle_method = false
            in_controller = false
            break
          end
        end

        # Stop looking if we hit another struct definition
        if in_controller && line.strip.starts_with?("struct ") && !line.includes?(controller_name)
          in_controller = false
          break
        end
      end
    end

    # Helper method to extract parameters with optional type annotations
    # Pattern: request.method_name("param") or request.method_name::<Type>("param")
    private def extract_typed_params(line : String, method_pattern : Regex, endpoint : Endpoint, param_type : String, existing_params : Set(String)? = nil)
      pattern = /#{method_pattern.source}(?:::<[^>]+>)?\("([^"]+)"\)/
      line.scan(pattern) do |match|
        param_name = match[1]
        # Only add if not already in existing params (for path parameters)
        next if existing_params && existing_params.includes?(param_name)
        endpoint.push_param(Param.new(param_name, "", param_type))
      end
    end
  end
end
