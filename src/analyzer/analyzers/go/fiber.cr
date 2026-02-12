require "./common"

module Analyzer::Go
  class Fiber < Common
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      groups = [] of Hash(String, String)
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
                  if File.exists?(path) && File.extname(path) == ".go"
                    # Read all lines for multi-line pattern support
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))
                      lexer = GolangLexer.new

                      analyze_group(line, lexer, groups)

                      # Use case-insensitive regex for HTTP method detection
                      # Matches patterns like: .GET(, .Get(, .get(, .POST(, .Post(, .post(, etc.
                      # Exclude parameter extraction patterns
                      if !line.includes?("Header.Get") && !line.includes?("Cookie.Get") &&
                         (match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD)\s*\(/i))
                        method = match[1].upcase
                        get_route_path(line, groups).tap do |route_path|
                          # Handle multi-line routes - check next lines if route is empty
                          if route_path.size == 0 && index + 1 < lines.size
                            next_line = lines[index + 1]
                            route_path = get_route_path(next_line, groups)
                          end

                          if route_path.size > 0
                            new_endpoint = Endpoint.new("#{route_path}", method, details)
                            if line.includes?("websocket.New(")
                              new_endpoint.protocol = "ws"
                            end
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      if line.includes?(".Query(") || line.includes?(".FormValue(")
                        get_param(line).tap do |param|
                          if param.name.size > 0 && last_endpoint.method != ""
                            last_endpoint.params << param
                          end
                        end
                      end

                      if line.includes?("Static(")
                        get_static_path(line).tap do |static_path|
                          if static_path["static_path"].size > 0 && static_path["file_path"].size > 0
                            public_dirs << static_path
                          end
                        end
                      end

                      if line.includes?("GetRespHeader(")
                        match = line.match(/GetRespHeader\(\"(.*)\"\)/)
                        if match
                          header_name = match[1]
                          last_endpoint.params << Param.new(header_name, "", "header")
                        end
                      end

                      if line.includes?("Vary(")
                        match = line.match(/Vary\(\"(.*)\"\)/)
                        if match
                          header_value = match[1]
                          last_endpoint.params << Param.new("Vary", header_value, "header")
                        end
                      end

                      if line.includes?("Cookies(")
                        match = line.match(/Cookies\(\"(.*)\"\)/)
                        if match
                          cookie_name = match[1]
                          last_endpoint.params << Param.new(cookie_name, "", "cookie")
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

      resolve_public_dirs(public_dirs)

      result
    end

    def get_param(line : String) : Param
      param_type = "json"
      if line.includes?("Query")
        param_type = "query"
      end
      if line.includes?("FormValue")
        param_type = "form"
      end

      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(")")
        if second.size > 1
          param_name = second[0].gsub("\"", "")
          rtn = Param.new(param_name, "", param_type)

          return rtn
        end
      end

      Param.new("", "", "")
    end
  end
end
