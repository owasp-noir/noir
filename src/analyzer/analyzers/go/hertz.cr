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
                      # Hertz routing methods are always uppercase (Go-style exported identifiers),
                      # so the regex is case-sensitive to avoid matching lowercase accessor calls
                      # like `someMap.get("x")` or `cookies.get("x")`.
                      if !line.includes?("Header.Get") && !line.includes?("Cookie.Get")
                        if match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD)\s*\(/)
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

                      ["Query", "PostForm", "GetHeader", "Param", "FormValue"].each do |pattern|
                        if line.includes?("#{pattern}(")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      if line.includes?("Static(")
                        add_static_path_if_valid(get_static_path(line), public_dirs)
                      end

                      # Read cookies via `ctx.Cookie("name")`. The leading `\.` avoids matching
                      # `SetCookie(...)` (which is for *writing* cookies, not extracting params).
                      if line.includes?("Cookie(")
                        if cookie_match = line.match(/\.Cookie\s*\(\s*"([^"]+)"/)
                          add_param_to_endpoint(Param.new(cookie_match[1], "", "cookie"), last_endpoint)
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

    # Regex-based extraction so nested calls (e.g. `fmt.Println(ctx.Query("x"))`)
    # and whitespace variants still yield the right param name, and so the
    # param-type derivation stays in one place.
    PARAM_ACCESSOR_RE = /(?:DefaultQuery|DefaultPostForm|Query|PostForm|GetHeader|Param|FormValue)\s*\(\s*"?([^",\s\)]+)"?/

    def get_param(line : String) : Param
      param_type = "json"
      param_type = "query" if line.includes?("Query(")
      param_type = "form" if line.includes?("PostForm(") || line.includes?("FormValue(")
      param_type = "header" if line.includes?("GetHeader(")
      param_type = "path" if line.includes?("Param(")

      if match = line.match(PARAM_ACCESSOR_RE)
        return Param.new(match[1], "", param_type)
      end

      Param.new("", "", "")
    end
  end
end
