require "../../../models/analyzer"

module Analyzer::Rust
  class Tide < Analyzer
    def analyze
      # Tide routing patterns: app.at("/path").get(handler), app.at("/path").post(handler), etc.

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
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      content = file.gets_to_end
                      endpoints = parse_tide_routes(content, path)
                      endpoints.each do |endpoint|
                        result << endpoint
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

    private def parse_tide_routes(content : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      
      # Find .at() method calls with chained HTTP methods
      # Pattern: .at("/path").get(), .at("/path").post(), etc.
      at_pattern = /\.at\s*\(\s*["']([^"']+)["']\s*\)\s*\.\s*(get|post|put|delete|patch|head|options)\s*\(/i
      
      content.scan(at_pattern) do |match|
        if match.size >= 3
          path = match[1]
          method = match[2].upcase
          
          # Parse path parameters (Tide uses :param syntax)
          params = [] of Param
          final_path = path.gsub(/:(\w+)/) do |param_match|
            param_name = param_match[1..-1] # Remove the ':'
            params << Param.new(param_name, "", "path")
            ":#{param_name}"
          end
          
          details = Details.new(PathInfo.new(file_path, 1))
          endpoints << Endpoint.new(final_path, method, params, details)
        end
      end
      
      # Also look for app initialization and route definitions in separate variables
      # Pattern: let route = app.at("/path"); route.get()
      route_var_pattern = /(\w+)\s*=\s*\w+\.at\s*\(\s*["']([^"']+)["']\s*\)/
      method_call_pattern = /(\w+)\s*\.\s*(get|post|put|delete|patch|head|options)\s*\(/i
      
      routes_map = {} of String => String
      
      # First pass: collect route variable assignments
      content.scan(route_var_pattern) do |match|
        if match.size >= 3
          var_name = match[1]
          path = match[2]
          routes_map[var_name] = path
        end
      end
      
      # Second pass: find method calls on route variables
      content.scan(method_call_pattern) do |match|
        if match.size >= 3
          var_name = match[1]
          method = match[2].upcase
          
          if routes_map.has_key?(var_name)
            path = routes_map[var_name]
            
            # Parse path parameters
            params = [] of Param
            final_path = path.gsub(/:(\w+)/) do |param_match|
              param_name = param_match[1..-1]
              params << Param.new(param_name, "", "path")
              ":#{param_name}"
            end
            
            details = Details.new(PathInfo.new(file_path, 1))
            endpoints << Endpoint.new(final_path, method, params, details)
          end
        end
      end
      
      endpoints
    rescue
      [] of Endpoint
    end
  end
end