require "../../engines/go_engine"

module Analyzer::Go
  # Pocketbase ships its own HTTP router under
  # `github.com/pocketbase/pocketbase/tools/router`. The DSL mirrors
  # Echo/Gin (`rg.GET("/x", handler)`, `rg.Group("/api")`), so the
  # shared `TreeSitterGoRouteExtractor` already handles the call
  # shapes — this analyzer just wires the import marker so noir
  # opts the framework's source files into the same pipeline. The marker
  # is the module root: a stock app imports only `pocketbase` and `core`
  # and registers on `se.Router` inside `app.OnServe().BindFunc(...)`.
  class Pocketbase < GoEngine
    analyzer_for "go_pocketbase"

    IMPORT_MARKER = "github.com/pocketbase/pocketbase"
    # `func bindBackupApi(app core.App, rg *router.RouterGroup[*core.RequestEvent])`.
    BUILDER_TYPE = "*router.RouterGroup"

    def analyze
      public_dirs = [] of Hash(String, String)
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      package_function_bodies = lazy_package_bodies(file_contents)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      # `apis.BindBackupApi(app, api)` with `api := se.Router.Group("/api")`:
      # the prefix lives at the call site (see `resolve_router_builder_prefixes`).
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      named_scope = named_handler_scope(file_contents)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, [] of String)

        cross_file_groups = ts_groups_for_directory(package_groups, dir)
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups)
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        route_rows = Set(Int32).new
        routes_by_line.each_key { |row| route_rows << row }
        external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups)
        # `sub.GET("/{key}", backupDownload)`: the handler's name, and the
        # request reads of its body (wherever it is declared).
        named = Noir::GoNamedHandler.new(content, path, ts_routes, named_scope)
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

        lines = GoEngine.strip_comments(content).lines
        # Routes' inline closures still open, innermost last: their
        # endpoints and the brace depth they close at. Braces are counted
        # with string and rune literals blanked (`fmt.Sprintf("{%s", x)`).
        closures = [] of {Array(Endpoint), Int32}
        depth = 0
        lines.each_with_index do |line, index|
          # Expanded router-builder bodies are emitted below with their call-site prefix.
          next if suppress_ranges.any?(&.includes?(index))
          next if named.claim?(index, line)
          code = line.gsub(LITERAL, %(""))
          delta = code.count('{') - code.count('}')
          details = Details.new(PathInfo.new(path, index + 1))
          route_eps = [] of Endpoint
          if ts_hits = routes_by_line[index]?
            ts_hits.each do |route|
              Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                endpoint = Endpoint.new(route.path, verb, details)
                if entries = callees_by_route[route.line]?
                  entries.each do |entry|
                    name, callee_path, callee_line = entry
                    endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end
                endpoint.handler = named.handler_for(route)
                endpoint.resolution = named.resolution_for(route)
                result << endpoint
                named.bind(route, endpoint)
                route_eps << endpoint
              end
            end
          end
          if !route_eps.empty? && code.matches?(/\bfunc\s*\(/)
            # A closure on the route line: its reads there are the route's,
            # and it stays open while its braces do.
            route_eps.each { |ep| add_request_reads(line, ep) }
            closures << {route_eps, depth} if delta > 0
          elsif route_eps.empty?
            closures.last?.try { |(eps, _)| eps.each { |ep| add_request_reads(line, ep) } }
          end
          depth += delta
          while (top = closures.last?) && depth <= top[1]
            closures.pop
          end
        end

        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named) { |line, ep| add_request_reads(line, ep) }
        named.each_attribution { |line, ep| add_request_reads(line, ep) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    # A Go string or rune literal on one line.
    LITERAL = /"(?:[^"\\]|\\.)*"|`[^`]*`|'(?:[^'\\]|\\.)*'/

    # `e.Request.URL.Query().Get("token")`, `e.Request.Header.Get("X-Key")`.
    private def add_request_reads(line : String, endpoint : Endpoint)
      Noir::GoRequestParamExtractor.query_params(line).each { |param| add_param_to_endpoint(param, endpoint) }
      Noir::GoRequestParamExtractor.header_params(line).each { |param| add_param_to_endpoint(param, endpoint) }
    end
  end
end
