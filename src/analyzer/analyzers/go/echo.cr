require "../../engines/go_engine"

module Analyzer::Go
  class Echo < GoEngine
    IMPORT_MARKER = "github.com/labstack/echo"

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      # Pre-pass for cross-file identifier-handler resolution. Built
      # once per analyze() so each per-file callee pass only does an
      # O(1) lookup into `package_function_bodies` rather than re-
      # walking every sibling source file.
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
                    next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Add", "Static"])
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Tree-sitter pre-pass: every Echo verb route
                    # (`e.GET`, `g.POST`, …) with its group prefix applied.
                    cross_file_groups = ts_groups_for_directory(package_groups, dir)
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Add")
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route in this file.
                    # Inline-closure handlers walk in place; bare
                    # identifier handlers fall through to sibling-file
                    # function bodies via the per-directory map.
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

                    # `e.Static("/url", "./dir")` — same shape as Gin/Fiber/etc.
                    Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
                      public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          # Echo's `e.Any` registers a route for every HTTP
                          # method — fan out so downstream formats see a real
                          # verb per endpoint instead of "ANY".
                          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                            new_endpoint = Endpoint.new(route.path, verb, details)
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

                      if line.includes?("Param(") || line.includes?("FormValue(")
                        add_param_to_endpoint(get_param(line), last_endpoint)
                      end

                      # `c.Bind(&v)` / `c.BindBody(...)` populate the
                      # request body. Echo also exposes `BindJSON`-style
                      # helpers via the echo-contrib package. Emit a
                      # single "body" indicator without trying to decode
                      # the bound struct's shape (would need static-type
                      # resolution we don't have).
                      if line.matches?(/\.Bind(?:Body|JSON|XML|YAML|Headers|Query|Path)?\s*\(/) &&
                         !line.includes?("// ")
                        add_param_to_endpoint(Param.new("body", "", "json"), last_endpoint)
                      end

                      if line.includes?("Request().Header.Get(")
                        match = line.match(/Request\(\)\.Header\.Get\(\"(.*)\"\)/)
                        if match
                          header_name = match[1]
                          last_endpoint.params << Param.new(header_name, "", "header")
                        end
                      end

                      if line.includes?("Cookie(") &&
                         !line.includes?("Header.Get") && !line.includes?("Query().Get") &&
                         !line.includes?("Request().Header.Get")
                        match = line.match(/Cookie\(\"(.*)\"\)/)
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
      if line.includes?("QueryParam")
        param_type = "query"
      end
      if line.includes?("FormValue")
        param_type = "form"
      end
      # `c.Param("id")` is Echo's path-variable accessor — `:id` URL
      # segments. Without this branch the helper defaulted to `json`,
      # which surfaced phantom JSON params (FP) alongside the
      # URL-derived path param for the same name.
      if line.includes?(".Param(") && !line.includes?("QueryParam")
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
