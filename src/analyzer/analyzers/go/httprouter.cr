require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Httprouter < Analyzer
    def analyze
      # Source Analysis
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        populate_channel_with_filtered_files(channel, ".go")

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  if File.exists?(path)
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Detect route definitions: router.GET("/path", handler), router.POST("/path", handler), etc.
                      if match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|Handle)\s*\(\s*"(\/[^"]*)"/)
                        method = match[1].upcase
                        route_path = match[2]

                        if method == "HANDLE"
                          # router.Handle("METHOD", "/path", handler) - extract method from first arg
                          if handle_match = line.match(/\.Handle\s*\(\s*"([^"]+)"\s*,\s*"(\/[^"]*)"/)
                            method = handle_match[1].upcase
                            route_path = handle_match[2]
                          else
                            next
                          end
                        end

                        if route_path.size > 0
                          new_endpoint = Endpoint.new(route_path, method, details)
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      elsif match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD)\s*\(/)
                        # Multi-line: method on this line, path on next line
                        method = match[1].upcase
                        if index + 1 < lines.size
                          next_line = lines[index + 1]
                          if path_match = next_line.match(/"(\/[^"]*)"/)
                            route_path = path_match[1]
                            if route_path.size > 0
                              new_endpoint = Endpoint.new(route_path, method, details)
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          end
                        end
                      end

                      # Parameter extraction: ps.ByName("param")
                      if line.includes?("ByName(")
                        if param_match = line.match(/ByName\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
                          param_name = param_match[1]
                          if param_name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << Param.new(param_name, "", "path")
                          end
                        end
                      end

                      # Query parameter: r.URL.Query().Get("name")
                      if line.includes?("Query().Get(")
                        if param_match = line.match(/Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
                          param_name = param_match[1]
                          if param_name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << Param.new(param_name, "", "query")
                          end
                        end
                      end

                      # Form parameter: r.PostFormValue("name")
                      if line.includes?("PostFormValue(")
                        if param_match = line.match(/PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
                          param_name = param_match[1]
                          if param_name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << Param.new(param_name, "", "form")
                          end
                        end
                      end

                      # Form/query parameter: r.FormValue("name")
                      if line.includes?("FormValue(") && !line.includes?("PostFormValue(")
                        if param_match = line.match(/FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
                          param_name = param_match[1]
                          if param_name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << Param.new(param_name, "", "query")
                          end
                        end
                      end

                      # Header parameter: r.Header.Get("name")
                      if line.includes?("Header.Get(")
                        if param_match = line.match(/Header\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
                          param_name = param_match[1]
                          if param_name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << Param.new(param_name, "", "header")
                          end
                        end
                      end

                      # Cookie parameter: r.Cookie("name")
                      if line.includes?("Cookie(")
                        if param_match = line.match(/Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
                          param_name = param_match[1]
                          if param_name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << Param.new(param_name, "", "cookie")
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
  end
end
