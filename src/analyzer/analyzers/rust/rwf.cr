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
                            # For rwf, we'll default to GET method since controllers handle method routing internally
                            endpoint = Endpoint.new(route_path, "GET", details)

                            # Extract path parameters from route pattern (e.g., /users/:id)
                            extract_path_params(route_path, endpoint)

                            # Look for controller implementation to extract more parameters
                            extract_controller_params(lines, controller_name, endpoint)

                            result << endpoint
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

    # Extract parameters from controller implementation
    def extract_controller_params(lines : Array(String), controller_name : String, endpoint : Endpoint)
      # Find the controller struct and its handle method
      in_controller = false
      in_handle_method = false
      brace_count = 0
      seen_opening_brace = false

      lines.each_with_index do |line, i|
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

          # Extract query parameters from request.query_parameter()
          if line.includes?("request.query_parameter(") || line.includes?("request.query_parameter")
            line.scan(/request\.query_parameter\("([^"]+)"\)/) do |match|
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
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
  end
end
