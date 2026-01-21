require "../../../models/analyzer"

module Analyzer::Crystal
  class Grip < Analyzer
    def analyze
      channel = Channel(String).new

      # Source Analysis
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
                  if File.exists?(path) && File.extname(path) == ".cr" && !path.includes?("lib")
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      last_endpoint = Endpoint.new("", "")
                      current_scopes = [] of String

                      file.each_line.with_index do |line, index|
                        details = Details.new(PathInfo.new(path, index + 1))

                        # Handle scope statements
                        if line.includes?("scope ") && line.includes?(" do")
                          scope_match = line.match(/scope\s+['"](.+?)['"]/)
                          if scope_match && scope_match[1]?
                            current_scopes << scope_match[1]
                          end
                        end

                        # Handle end statements (basic detection)
                        if line.strip == "end" && current_scopes.size > 0
                          current_scopes.pop
                        end

                        # Parse HTTP method calls
                        endpoint = line_to_endpoint(line, current_scopes)
                        if endpoint.method != ""
                          endpoint.details = details
                          result << endpoint
                          last_endpoint = endpoint
                        end

                        # Parse parameters
                        param = line_to_param(line)
                        if param.name != ""
                          if last_endpoint.method != ""
                            last_endpoint.push_param(param)
                          end
                        end

                        # Parse WebSocket routes
                        ws_endpoint = line_to_websocket(line, current_scopes)
                        if ws_endpoint.url != ""
                          ws_endpoint.details = details
                          result << ws_endpoint
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
        logger.debug e
      end

      result
    end

    def line_to_param(content : String) : Param
      # Grip context parameter parsing
      if content.includes?("context.fetch_path_params")
        # Extract parameter name from context.fetch_path_params["param_name"]
        if match = content.match(/context\.fetch_path_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "path")
        end
      end

      if content.includes?("context.fetch_query_params")
        if match = content.match(/context\.fetch_query_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "query")
        end
      end

      if content.includes?("context.fetch_form_params")
        if match = content.match(/context\.fetch_form_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "form")
        end
      end

      if content.includes?("context.fetch_json_params")
        if match = content.match(/context\.fetch_json_params\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "json")
        end
      end

      if content.includes?("context.fetch_headers")
        if match = content.match(/context\.fetch_headers\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "header")
        end
      end

      if content.includes?("context.fetch_cookies")
        if match = content.match(/context\.fetch_cookies\["(.+?)"\]/)
          param_name = match[1]
          return Param.new(param_name, "", "cookie")
        end
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String, scopes : Array(String)) : Endpoint
      scope_prefix = scopes.join("")

      # Match HTTP method calls: get "/path", Controller
      %w[get post put patch delete options head].each do |method|
        if content.includes?("#{method} ") && content.includes?("\"")
          if match = content.match(/#{method}\s+['"](.+?)['"]/)
            path = match[1]
            full_path = scope_prefix + path
            return Endpoint.new(full_path, method.upcase)
          end
        end
      end

      Endpoint.new("", "")
    end

    def line_to_websocket(content : String, scopes : Array(String)) : Endpoint
      scope_prefix = scopes.join("")

      if content.includes?("ws ") && content.includes?("\"")
        if match = content.match(/ws\s+['"](.+?)['"]/)
          path = match[1]
          full_path = scope_prefix + path
          endpoint = Endpoint.new(full_path, "GET")
          endpoint.protocol = "ws"
          return endpoint
        end
      end

      Endpoint.new("", "")
    end
  end
end
