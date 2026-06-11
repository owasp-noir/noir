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
    HTTP_METHODS_ALLOWED  = (HTTP_METHODS_EXPANDED + %w[TRACE CONNECT QUERY ANY]).to_set
    IMPORT_MARKER         = "github.com/cloudwego/hertz"

    def analyze
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      package_function_bodies = collect_package_function_bodies(file_contents)
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            get_files_by_extension(".go").each { |file| channel.send(file) }
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if GoEngine.go_test_file?(path)
                  if File.exists?(path)
                    content = file_contents[path]? || read_file_content(path)
                    dir = File.dirname(path)
                    next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Handle", "Static"])
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Tree-sitter pre-pass. Hertz's `.Any("/path", ...)`
                    # comes through as verb="ANY" and we fan it out to
                    # every HTTP method below — matching the legacy
                    # behaviour.
                    cross_file_groups = ts_groups_for_directory(package_groups, dir)
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Handle")
                      .select { |route| HTTP_METHODS_ALLOWED.includes?(route.verb) }
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route (see Gin).
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(
                      callees_needed?,
                      content,
                      path,
                      route_rows,
                      external_fns,
                      imported_functions: import_path_function_bodies
                    )

                    # `h.Static("/url", "./dir")`.
                    Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
                      public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          callee_entries = callees_by_route[route.line]?
                          if route.verb == "ANY"
                            HTTP_METHODS_EXPANDED.each do |m|
                              new_endpoint = Endpoint.new(route.path, m, details)
                              callee_entries.try &.each do |entry|
                                name, callee_path, callee_line = entry
                                new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          else
                            new_endpoint = Endpoint.new(route.path, route.verb, details)
                            callee_entries.try &.each do |entry|
                              name, callee_path, callee_line = entry
                              new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                            end
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      ["Query", "PostForm", "GetHeader", "Param", "FormValue"].each do |pattern|
                        if line.includes?("#{pattern}(")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      # Read cookies via `ctx.Cookie("name")`. The leading `\.` avoids matching
                      # `SetCookie(...)` (which is for *writing* cookies, not extracting params).
                      if line.includes?("Cookie(")
                        if cookie_match = line.match(/\.Cookie\s*\(\s*"([^"]+)"/)
                          add_param_to_endpoint(Param.new(cookie_match[1], "", "cookie"), last_endpoint)
                        end
                      end

                      # Hertz body-binding helpers populate the request
                      # body from JSON/form/etc. Surface a single "body"
                      # indicator — the bound struct's fields are not
                      # statically resolvable here. `And\w+` catches
                      # `BindAndValidate`.
                      if line.matches?(/\.Bind(?:JSON|Query|Header|Form|Protobuf|And\w+)?\s*\(/)
                        add_param_to_endpoint(Param.new("body", "", "json"), last_endpoint)
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
