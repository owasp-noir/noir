require "../../engines/go_engine"

module Analyzer::Go
  class Echo < GoEngine
    analyzer_for "go_echo"

    IMPORT_MARKER = "github.com/labstack/echo"
    BUILDER_TYPE  = "*echo.Group"

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
      # `RegisterUsers(e.Group("/api/v1"))` + `func RegisterUsers(g *echo.Group)`:
      # the prefix lives at the call site (see `resolve_router_builder_prefixes`).
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if GoEngine.go_test_file?(base_relative_path(path))
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Add", "Match", "Static", "File"])
        lines = GoEngine.strip_comments(content).lines
        last_endpoints = [] of Endpoint

        # Tree-sitter pre-pass: every Echo verb route
        # (`e.GET`, `g.POST`, …) with its group prefix applied.
        cross_file_groups = ts_groups_for_directory(package_groups, dir)
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
          content,
          cross_file_groups,
          handle_method: "Add",
          handle_many_methods: ["Match"]
        )
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        named = Noir::GoNamedHandler.new(content, path, ts_routes)
        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups)
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

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

        # `e.File("/url", "disk/path")` — single-file static route.
        Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content, method_name: "File").each do |sp|
          public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
        end

        lines.each_with_index do |line, index|
          # Expanded router-builder bodies are emitted below with their
          # call-site prefix.
          next if suppress_ranges.any?(&.includes?(index))
          next if named.claim?(index, line)

          details = Details.new(PathInfo.new(path, index + 1))

          if ts_hits = routes_by_line[index]?
            last_endpoints = [] of Endpoint
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
                named.bind(route, new_endpoint)
                last_endpoints << new_endpoint
              end
            end
          end

          last_endpoints.each { |ep| add_echo_param_patterns(line, ep) }
        end

        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named, "Add") do |line, ep|
          add_echo_param_patterns(line, ep)
        end

        named.each_attribution { |line, ep| add_echo_param_patterns(line, ep) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    private def add_echo_param_patterns(line : String, ep : Endpoint)
      if line.includes?("Param(") || line.includes?("FormValue(")
        add_param_to_endpoint(get_param(line), ep)
      end

      # `c.Bind(&v)` / `c.BindBody(...)` populate the
      # request body. Echo also exposes `BindJSON`-style
      # helpers via the echo-contrib package. Emit a
      # single "body" indicator without trying to decode
      # the bound struct's shape (would need static-type
      # resolution we don't have).
      if line.matches?(/\.Bind(?:Body|JSON|XML|YAML|Headers|Query|Path)?\s*\(/) &&
         !line.includes?("// ")
        add_param_to_endpoint(Param.new("body", "", "json"), ep)
      end

      if line.includes?("Request().Header.Get(")
        match = line.match(/Request\(\)\.Header\.Get\(\s*\"(.*)\"\s*\)/)
        if match
          ep.params << Param.new(match[1], "", "header")
        end
      end

      if line.includes?("Cookie(") &&
         !line.includes?("Header.Get") && !line.includes?("Query().Get") &&
         !line.includes?("Request().Header.Get")
        match = line.match(/Cookie\(\s*\"(.*)\"\s*\)/)
        if match
          ep.params << Param.new(match[1], "", "cookie")
        end
      end
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
          param_name = second[0].gsub("\"", "").strip
          rtn = Param.new(param_name, "", param_type)

          return rtn
        end
      end

      Param.new("", "", "")
    end
  end
end
