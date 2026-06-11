require "../../engines/go_engine"

module Analyzer::Go
  class Fiber < GoEngine
    IMPORT_MARKER = "github.com/gofiber/fiber"

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      package_function_bodies = collect_package_function_bodies(file_contents)
      package_method_bodies = collect_package_controller_method_bodies(file_contents)
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      import_path_method_bodies = collect_import_path_method_bodies(package_method_bodies)
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
                    next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Add", "Static"])
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Tree-sitter pre-pass for Fiber's verb-method routes.
                    # websocket.New(...) detection stays on the raw line text
                    # because it's a sibling expression, not part of the route
                    # argument list.
                    cross_file_groups = ts_groups_for_directory(package_groups, dir)
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Add")
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route (see Gin).
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
                    external_methods = ts_controller_method_bodies_for_directory(package_method_bodies, dir)
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(
                      callees_needed?,
                      content,
                      path,
                      route_rows,
                      external_fns,
                      external_methods,
                      imported_functions: import_path_function_bodies,
                      imported_methods: import_path_method_bodies
                    )

                    # `app.Static("/url", "./dir")`.
                    Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
                      public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                            new_endpoint = Endpoint.new(route.path, verb, details)
                            new_endpoint.protocol = "ws" if route.handler.includes?("websocket.New(")
                            if entries = callees_by_route[route.line]?
                              entries.each do |entry|
                                name, callee_path, callee_line = entry
                                new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                            end
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      if line.includes?(".Query(") || line.includes?(".FormValue(") ||
                         line.includes?(".Params(") || line.includes?(".ParamsInt(")
                        add_param_to_endpoint(get_param(line), last_endpoint)
                      end

                      # Fiber's body-binding helpers: `c.BodyParser(&v)`
                      # for arbitrary content negotiation, plus the
                      # explicit `c.QueryParser` / `c.ReqHeaderParser`
                      # /`c.CookieParser` /`c.ParamsParser` variants that
                      # parse into a struct. `BodyParser` is the one
                      # that signals a request body is expected; the
                      # others duplicate accessors we already surface.
                      if line.includes?(".BodyParser(")
                        add_param_to_endpoint(Param.new("body", "", "json"), last_endpoint)
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

                      if line.includes?("Cookies(") &&
                         !line.includes?("Header.Get") && !line.includes?("Cookie.Get")
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
      # `c.Params("id")` — Fiber path-variable accessor (also
      # `.ParamsInt("id")`). Distinct from `c.Query`/`c.FormValue`;
      # was previously falling through to the `json` default.
      if line.includes?(".Params(") || line.includes?(".ParamsInt(")
        param_type = "path"
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
