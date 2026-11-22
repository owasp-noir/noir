require "../../engines/go_engine"

module Analyzer::Go
  class Echo < GoEngine
    analyzer_for "go_echo"

    IMPORT_MARKER = "github.com/labstack/echo"
    BUILDER_TYPE  = "*echo.Group"
    # Struct field types that hold a router (`s.echo.GET(...)`).
    ROUTER_TYPES = {IMPORT_MARKER => %w[Echo Group]}

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Other packages' exported string constants (`e.Group(apiv2.GroupPrefix)`).
      string_seed = go_string_seed
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER, string_seed: string_seed)
      # Pre-pass for cross-file identifier-handler resolution. Built
      # once per analyze() so each per-file callee pass only does an
      # O(1) lookup into `package_function_bodies` rather than re-
      # walking every sibling source file.
      package_function_bodies = collect_package_function_bodies(file_contents)
      package_method_bodies = collect_package_controller_method_bodies(file_contents)
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      import_path_method_bodies = collect_import_path_method_bodies(package_method_bodies)
      # `RegisterUsers(e.Group("/api/v1"))` + `func RegisterUsers(g *echo.Group)`:
      # the prefix lives at the call site (see `resolve_router_builder_prefixes`).
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      named_scope = named_handler_scope(file_contents, infer_module: true)
      resolver = Noir::GoRequestParamExtractor::Resolver.new(named_scope.bodies, file_contents, named_scope.import_dirs, "echo", named_scope.structs)
      router_fields = package_router_fields(file_contents, ROUTER_TYPES, named_scope.import_dirs, package_groups)
      each_framework_route_file(file_contents, framework_dirs, IMPORT_MARKER, ["Add", "Match", "Static", "File"]) do |path, content, dir|
        lines = GoEngine.strip_comments(content).lines
        last_endpoints = [] of Endpoint

        # Tree-sitter pre-pass: every Echo verb route
        # (`e.GET`, `g.POST`, …) with its group prefix applied.
        receivers, cross_file_groups = file_router_receivers(router_fields, path, content, ts_groups_for_directory(package_groups, dir))
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
          content,
          cross_file_groups,
          handle_method: "Add",
          handle_many_methods: ["Match"],
          string_seed: string_seed,
          literal_join: true,
          router_fields: receivers
        )
        # A helper's routes on a group no call site gave a readable prefix (#3567).
        by_name = Set({Int32, String}).new
        unread = unread_builder_routes(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups, "Add", string_seed, literal_join: true, by_name: by_name)
        ts_routes.map! do |route|
          key = {route.line, route.path}
          route.unresolve_prefix! if unread.includes?(key)
          route.prefix_heuristic = true if by_name.includes?(key)
          route
        end unless unread.empty? && by_name.empty?
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        # Echo takes `GET(path, h, m...)`: the handler comes first.
        named = go_named_handler(content, path, ts_routes, named_scope, handler_first: true)
        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups)
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

        # Resolve 1-hop callees for every route in this file.
        # Inline-closure handlers walk in place; bare
        # identifier handlers fall through to sibling-file
        # function bodies via the per-directory map.
        route_offsets = ts_routes.map(&.offset).to_set
        external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
        external_methods = ts_controller_method_bodies_for_directory(package_method_bodies, dir)
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(
          callees_needed?,
          content,
          path,
          route_offsets,
          external_fns,
          external_methods,
          imported_functions: import_path_function_bodies,
          imported_methods: import_path_method_bodies
        )

        # `e.Static("/url", "./dir")` — same shape as Gin/Fiber/etc.
        Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
          public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
        end

        # `e.File("/url", "disk/path")` — single-file static route.
        Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content, method_name: "File").each do |sp|
          public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
        end

        # The lines credited to `last_endpoints` since their route, read as
        # one body when the next route starts (or the file ends).
        segment = [] of String
        each_route_line(lines, routes_by_line) do |line, index, ts_hits|
          # Expanded router-builder bodies are emitted below with their
          # call-site prefix.
          next if suppress_ranges.any?(&.includes?(index))
          next if named.claim?(index, line)

          if ts_hits
            add_echo_body_params(segment, path, last_endpoints, resolver)
            segment = [] of String
            last_endpoints = [] of Endpoint
            ts_hits.each do |route|
              details = go_route_details(route, path, content)
              # Echo's `e.Any` registers a route for every HTTP
              # method — fan out so downstream formats see a real
              # verb per endpoint instead of "ANY".
              Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                new_endpoint = Endpoint.new(route.path, verb, details)
                if entries = callees_by_route[route.offset]?
                  entries.each do |entry|
                    name, callee_path, callee_line = entry
                    new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end
                new_endpoint.handler = named.handler_for(route)
                new_endpoint.resolution = named.resolution_for(route)
                result << new_endpoint
                named.bind(route, new_endpoint)
                last_endpoints << new_endpoint
              end
            end
          end

          segment << line
        end
        add_echo_body_params(segment, path, last_endpoints, resolver)

        builder_bodies = Hash(UInt64, Tuple(Endpoint, Array(String))).new
        expand_router_builders(content, path, expand_builders, callees_by_route, named, "Add", string_seed: string_seed, literal_join: true) do |line, ep|
          (builder_bodies[ep.params.object_id] ||= {ep, [] of String})[1] << line
        end
        builder_bodies.each_value { |(ep, body_lines)| add_echo_body_params(body_lines, path, [ep], resolver) }

        named.each_attribution { |line, ep| add_echo_param_patterns(line, ep) }
        named.each_bound_body(direct_only: true) { |file, body_lines, eps| add_binding_params(body_lines, file, eps, resolver) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    private def add_echo_body_params(lines, file, eps, resolver)
      lines.each { |line| eps.each { |ep| add_echo_param_patterns(line, ep) } }
      add_binding_params(lines, file, eps, resolver)
    end

    private def add_echo_param_patterns(line : String, ep : Endpoint)
      if line.includes?("Param(") || line.includes?("FormValue(") || line.includes?("FormFile(")
        # Every accessor on the line (`f(c.QueryParam("a"), c.QueryParam("b"))`).
        line.scan(ACCESSOR_RE) do |m|
          param = Param.new(m[2].gsub("\"", "").strip, "", ACCESSOR_TYPES[m[1]])
          # `FormValue` is net/http's: the body is parsed only for POST, PUT
          # and PATCH, so on any other method it reads the query string.
          param.param_type = "query" if m[1] == "FormValue" && !FORM_BODY_METHODS.includes?(ep.method)
          # A shared helper may read a path variable this route has no slot for.
          if param.param_type != "path" || ep.url.includes?(param.name == "*" ? "*" : ":#{param.name}")
            add_param_to_endpoint(param, ep)
          end
        end
      end
      # `c.QueryParams().Get("from")`, `c.Request().URL.Query()["id"]`.
      Noir::GoRequestParamExtractor.query_params(line).each { |param| add_param_to_endpoint(param, ep) }

      Noir::GoRequestParamExtractor.header_params(line).each { |header| add_param_to_endpoint(header, ep) }

      if line.includes?("Cookie(") &&
         !line.includes?("Header.Get") && !line.includes?("Query().Get") &&
         !line.includes?("Request().Header.Get")
        match = line.match(/Cookie\(\s*\"(.*)\"\s*\)/)
        if match
          add_param_to_endpoint(Param.new(match[1], "", "cookie"), ep)
        end
      end
    end

    FORM_BODY_METHODS = %w[POST PUT PATCH]

    ACCESSOR_RE    = /\b(QueryParam|FormValue|FormFile|Param)\s*\(([^()]*)\)/
    ACCESSOR_TYPES = {"QueryParam" => "query", "FormValue" => "form", "FormFile" => "form", "Param" => "path"}

    # The accessor's own argument, so one nested in another call
    # (`c.String(200, c.QueryParam("color"))`) still resolves.
    # `c.Param("id")` is Echo's path-variable accessor (`:id` segments).
    def get_param(line : String) : Param
      if m = line.match(ACCESSOR_RE)
        return Param.new(m[2].gsub("\"", "").strip, "", ACCESSOR_TYPES[m[1]])
      end
      Param.new("", "", "")
    end
  end
end
