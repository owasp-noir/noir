require "../../../models/analyzer"

module Analyzer::Crystal
  class Marten < Analyzer
    def analyze
      # Public Dir Analysis - static files
      begin
        get_public_files(@base_path).each do |file|
          # Extract the path after "/public/" regardless of depth
          if file =~ /\/public\/(.*)/
            relative_path = $1
            @result << Endpoint.new("/#{relative_path}", "GET")
          end
        end
      rescue e
        logger.debug e
      end

      channel = Channel(String).new
      populate_channel_with_files(channel)

      # Source Analysis
      begin
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
                      file.each_line.with_index do |line, index|
                        # Parse route definitions
                        endpoint = line_to_endpoint(line)
                        if endpoint.method != ""
                          details = Details.new(PathInfo.new(path, index + 1))
                          endpoint.details = details
                          result << endpoint
                          last_endpoint = endpoint
                        end

                        # Parse parameter usage
                        param = line_to_param(line)
                        if param.name != ""
                          if last_endpoint.method != ""
                            last_endpoint.push_param(param)
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
      rescue e
        logger.debug e
      end

      result
    end

    def line_to_param(content : String) : Param
      # Query parameters: request.query_params["param"]
      if content.includes? "request.query_params["
        param = content.split("request.query_params[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      # Form/JSON data: request.data["param"]
      if content.includes? "request.data["
        param = content.split("request.data[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "form")
      end

      # Headers: request.headers["header"]
      if content.includes? "request.headers["
        param = content.split("request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      # Cookies: request.cookies["cookie"]
      if content.includes? "request.cookies["
        param = content.split("request.cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      # Path parameters: params["param"]
      if content.includes? "params["
        param = content.split("params[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "path")
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String) : Endpoint
      # Parse Marten route definitions: path "/route", Handler
      content.scan(/path\s+['"](.+?)['"]/) do |match|
        if match.size > 1
          route = match[1].to_s

          # Extract HTTP methods from handler class patterns
          # For now, assume GET for routes, but could be enhanced to detect handler methods
          return Endpoint.new(route, "GET")
        end
      end

      # Parse handler method definitions for specific HTTP methods
      content.scan(/def\s+(get|post|put|delete|patch|head|options)\s*/) do |match|
        if match.size > 1
          method = match[1].to_s.upcase
          # Note: For handler methods, we'd need to associate them with routes
          # This is a simplified version that just detects method handlers exist
          return Endpoint.new("", method)
        end
      end

      Endpoint.new("", "")
    end
  end
end
