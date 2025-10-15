require "../../../models/analyzer"

module Analyzer::Rust
  class Rocket < Analyzer
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
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      file.each_line.with_index do |line, index|
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
                              result << Endpoint.new("#{route_argument}", callback_to_method(callback_argument), params, details)
                            rescue
                            end
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

    def callback_to_method(str)
      method = str.split("(").first
      if !["get", "post", "put", "patch", "delete"].includes?(method)
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
  end
end
