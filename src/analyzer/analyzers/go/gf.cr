require "./common"

module Analyzer::Go
  class Gf < Common
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

                      if line.includes?(".BindHandler(") || line.includes?(".BindMiddleware(")
                        get_route_path(line, groups).tap do |route_path|
                          if route_path.size > 0
                            new_endpoint = Endpoint.new("#{route_path}", "ALL", details)
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      # Exclude logger matches or variable assignments like err = ... or info := ...
                      if !line.includes?("logger.") && (match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|TRACE|ALL)\s*\(/i))
                        method = match[1].upcase
                        get_route_path(line, groups).tap do |route_path|
                          # Handle multi-line routes - check next lines if route is empty
                          if route_path.size == 0 && index + 1 < lines.size
                            next_line = lines[index + 1]
                            route_path = get_route_path(next_line, groups)
                          end

                          if route_path.size > 0
                            new_endpoint = Endpoint.new("#{route_path}", method, details)
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      ["Get", "GetQuery", "GetForm", "GetHeader", "GetUploadFile"].each do |pattern|
                        if line.includes?("#{pattern}(") && !line.includes?("Cookie.Get")
                          get_param(line).tap do |param|
                            if param.name.size > 0 && last_endpoint.method != ""
                              last_endpoint.params << param
                            end
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

                      if line.includes?("Cookie.Get(")
                        match = line.match(/Cookie\.Get\(\"(.*)\"\)/)
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
      if line.includes?("GetQuery(")
        param_type = "query"
      end
      if line.includes?("GetForm(") || line.includes?("GetUploadFile(")
        param_type = "form"
      end
      if line.includes?("GetHeader(")
        param_type = "header"
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
