require "../../engines/go_engine"

module Analyzer::Go
  class Hertz < GoEngine
    # Hertz (https://github.com/cloudwego/hertz) mirrors Gin's routing API:
    #   h := server.Default()
    #   h.GET("/ping", handler)
    #   h.Any("/path", handler)           -- expands to all HTTP methods
    #   g := h.Group("/api/v1"); g.GET(...)
    # and uses the same parameter accessors on the RequestContext:
    #   ctx.Query / DefaultQuery / PostForm / DefaultPostForm / GetHeader / Cookie
    HTTP_METHODS_EXPANDED = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]

    def analyze
      public_dirs = [] of (Hash(String, String))
      package_groups, file_lines_cache = collect_package_groups
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
                    lines = file_lines_cache[path]? || File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    groups = groups_for_directory(package_groups, File.dirname(path))

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Route definitions — skip parameter accessors (Header.Get, Cookie.Get).
                      if !line.includes?("Header.Get") && !line.includes?("Cookie.Get")
                        if match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD)\s*\(/i)
                          method = match[1].upcase
                          route_path = get_route_path(line, groups)
                          if route_path.size == 0 && index + 1 < lines.size
                            route_path = get_route_path(lines[index + 1], groups)
                          end

                          if route_path.size > 0
                            new_endpoint = Endpoint.new(route_path, method, details)
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        elsif line.match(/\.Any\s*\(/)
                          # .Any("/path", ...) registers the handler for every HTTP method.
                          route_path = get_route_path(line, groups)
                          if route_path.size == 0 && index + 1 < lines.size
                            route_path = get_route_path(lines[index + 1], groups)
                          end

                          if route_path.size > 0
                            HTTP_METHODS_EXPANDED.each do |m|
                              new_endpoint = Endpoint.new(route_path, m, details)
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          end
                        end
                      end

                      ["Query", "PostForm", "GetHeader"].each do |pattern|
                        if line.includes?("#{pattern}(")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      if line.includes?("Static(")
                        add_static_path_if_valid(get_static_path(line), public_dirs)
                      end

                      if line.includes?("Cookie(")
                        if cookie_match = line.match(/Cookie\(\"(.*)\"\)/)
                          last_endpoint.params << Param.new(cookie_match[1], "", "cookie")
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
      param_type = "query" if line.includes?("Query(")
      param_type = "form" if line.includes?("PostForm(")
      param_type = "header" if line.includes?("GetHeader(")

      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(")")
        if second.size > 1
          if line.includes?("DefaultQuery") || line.includes?("DefaultPostForm")
            param_name = second[0].split(",")[0].gsub("\"", "")
          else
            param_name = second[0].gsub("\"", "")
          end
          return Param.new(param_name, "", param_type)
        end
      end

      Param.new("", "", "")
    end
  end
end
