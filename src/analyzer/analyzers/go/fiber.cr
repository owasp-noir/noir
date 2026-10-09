require "../../engines/go_engine"

module Analyzer::Go
  class Fiber < GoEngine
    analyzer_for "go_fiber"

    IMPORT_MARKER = "github.com/gofiber/fiber"
    BUILDER_TYPE  = "fiber.Router"

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      package_function_bodies = collect_package_function_bodies(file_contents)
      package_method_bodies = collect_package_controller_method_bodies(file_contents)
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      import_path_method_bodies = collect_import_path_method_bodies(package_method_bodies)
      # `RegisterUsers(app.Group("/api"))` + `func RegisterUsers(r fiber.Router)`:
      # the prefix lives at the call site (see `resolve_router_builder_prefixes`).
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if GoEngine.go_test_file?(base_relative_path(path))
        next unless File.exists?(path)
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
        # `app.Route("/r", func(r fiber.Router){...})` scopes a prefix to
        # the closure; `app.Mount("/mnt", micro)` prefixes a sub-app.
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
          content, cross_file_groups, handle_method: "Add",
          closure_group_methods: ["Route"], mount_methods: ["Mount"])
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        named = Noir::GoNamedHandler.new(content, path, ts_routes)
        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups)
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

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
          # Expanded router-builder bodies are emitted below with their
          # call-site prefix.
          next if suppress_ranges.any?(&.includes?(index))
          next if named.claim?(index, line)

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
                named.bind(route.handler, new_endpoint)
                last_endpoint = new_endpoint
              end
            end
          end

          add_fiber_param_patterns(line, last_endpoint)
        end

        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named, "Add") do |line, ep|
          add_fiber_param_patterns(line, ep)
        end

        named.each_attribution { |line, ep| add_fiber_param_patterns(line, ep) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    private def add_fiber_param_patterns(line : String, ep : Endpoint)
      if line.includes?(".Query(") || line.includes?(".FormValue(") ||
         line.includes?(".Params(") || line.includes?(".ParamsInt(")
        add_param_to_endpoint(get_param(line), ep)
      end

      # Fiber's body-binding helpers: `c.BodyParser(&v)`
      # for arbitrary content negotiation, plus the
      # explicit `c.QueryParser` / `c.ReqHeaderParser`
      # /`c.CookieParser` /`c.ParamsParser` variants that
      # parse into a struct. `BodyParser` is the one
      # that signals a request body is expected; the
      # others duplicate accessors we already surface.
      if line.includes?(".BodyParser(")
        add_param_to_endpoint(Param.new("body", "", "json"), ep)
      end

      if line.includes?("GetRespHeader(")
        match = line.match(/GetRespHeader\(\"(.*)\"\)/)
        if match
          ep.params << Param.new(match[1], "", "header")
        end
      end

      if line.includes?("Vary(")
        match = line.match(/Vary\(\"(.*)\"\)/)
        if match
          ep.params << Param.new("Vary", match[1], "header")
        end
      end

      if line.includes?("Cookies(") &&
         !line.includes?("Header.Get") && !line.includes?("Cookie.Get")
        match = line.match(/Cookies\(\"(.*)\"\)/)
        if match
          ep.params << Param.new(match[1], "", "cookie")
        end
      end
    end

    def get_param(line : String) : Param
      param_type = "json"
      if line.includes?("Query")
        param_type = "query"
      elsif line.includes?("FormValue")
        param_type = "form"
      elsif line.includes?(".Params(") || line.includes?(".ParamsInt(")
        param_type = "path"
      end

      # Capture the accessor's first string-literal argument.
      # Skip route registrations like `app.Query("/search", handler)`.
      if match = line.match(/\.(?:Query|FormValue|Params|ParamsInt)\s*\(\s*"([^"]*)"/)
        param_name = match[1]
        return Param.new("", "", "") if param_name.starts_with?("/")

        return Param.new(param_name, "", param_type)
      end

      Param.new("", "", "")
    end
  end
end
