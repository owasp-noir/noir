require "../../engines/go_engine"

module Analyzer::Go
  class Mux < GoEngine
    analyzer_for "go_mux"

    # `github.com/minio/mux` is a maintained hard fork of gorilla/mux with
    # the same `Methods(...).Path(...).HandlerFunc(...)` / `Subrouter()`
    # API, so the same extraction applies. MinIO itself imports only the
    # fork: the detector still fired (gorilla/mux is an indirect entry in
    # its go.mod) but every file failed this gate, so the whole S3 data
    # plane — `HEAD/GET/PUT/POST/DELETE /{object}` and the `_MINIO_*`
    # internal routes — reported zero endpoints.
    IMPORT_MARKER = ["github.com/gorilla/mux", "github.com/minio/mux"]
    BUILDER_TYPE  = "*mux.Router"

    # Registration calls that make a file worth the route parse.
    ROUTE_METHODS = ["Handle", "HandleFunc", "Path", "PathPrefix", "Methods", "Queries"]

    private def extract_mux_routes(content : String, cross_file_groups : Hash(String, String), string_seed : Hash(String, String)) : Array(Noir::TreeSitterGoRouteExtractor::Route)
      Noir::TreeSitterGoRouteExtractor.extract_routes(
        content, cross_file_groups,
        string_seed: string_seed,
        group_method: "Subrouter",
        handlefunc_methods: true,
        # gorilla/mux registers nothing through a verb-named method —
        # `Router.Get(name)` looks a named route up — so `.Get("X", …)` /
        # `.Any("k", v)` on env readers, caches and loggers are not routes
        # (minio's `env.Get("_MINIO_SCANNER", …)`, mattermost's
        # `mlog.Any("panic", r)`).
        verb_calls: false,
      )
    end

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Mux subrouters are created via the two-call chain
      # `api := r.PathPrefix("/api/").Subrouter()`. The engine fixpoint
      # treats "Subrouter" as the grouping method and peeks through the
      # chain to read the PathPrefix argument.
      # Paths built through wrappers (`s.prefixedPath("/version")`) and
      # other packages' constants (see Gin).
      string_seed = go_string_seed(mark_wrappers: true)
      package_groups, file_contents = collect_package_groups_ts("Subrouter", import_marker: IMPORT_MARKER, string_seed: string_seed)
      # `InitUser(r.PathPrefix("/api/users").Subrouter())` + `func InitUser(users *mux.Router)`:
      # the prefix lives at the call site (see `resolve_router_builder_prefixes`).
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      # Mux's HandleFunc/Methods chain stores `route.line` on the
      # HandleFunc call_expression itself, so the row-keyed callee
      # lookup matches it cleanly.
      package_function_bodies = lazy_package_bodies(file_contents)
      # Mux handlers are almost always method values (`as.Campaigns`) or
      # wrapped method values (`mid.Use(as.Users, ...)`); resolve them to
      # their method bodies so callees/ai-context aren't empty.
      package_method_bodies = lazy_package_bodies(file_contents)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      # Route and static-file parses of every candidate file, on the worker
      # threads; the pass below consumes them (see `prefetch_route_sources`).
      prefetched = prefetch_route_sources(file_contents, framework_dirs, IMPORT_MARKER, ROUTE_METHODS, verb_calls: false) do |path, content|
        {extract_mux_routes(content, ts_groups_for_directory(package_groups, File.dirname(path)), string_seed),
         Noir::TreeSitterGoRouteExtractor.extract_mux_statics(content)}
      end
      named_scope = named_handler_scope(file_contents)
      resolver = Noir::GoRequestParamExtractor::Resolver.new(named_scope.bodies, file_contents, named_scope.import_dirs)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ROUTE_METHODS, verb_calls: false)
        lines = GoEngine.strip_comments(content).lines
        last_endpoint = Endpoint.new("", "")

        ts_routes, statics = prefetched[path]? ||
                             {extract_mux_routes(content, ts_groups_for_directory(package_groups, dir), string_seed),
                              Noir::TreeSitterGoRouteExtractor.extract_mux_statics(content)}
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        named = Noir::GoNamedHandler.new(content, path, ts_routes, named_scope)
        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, ts_groups_for_directory(package_groups, dir))
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

        # Resolve 1-hop callees for every route (see Gin).
        route_rows = Set(Int32).new
        routes_by_line.each_key { |row| route_rows << row }
        external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
        external_methods = ts_controller_method_bodies_for_directory(package_method_bodies, dir)
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns, external_methods)
        # Every mux handler is a stdlib one: read it as net/http's are.
        params_by_route = Noir::GoRequestParamExtractor.params_for_routes(content, route_rows,
          ts_routes.to_h { |r| {r.line, r.verb} }, named_scope.bodies.functions_for(dir), named_scope.bodies.methods_for(dir),
          resolver: resolver, path: path)

        # Mux static-file: `r.PathPrefix("/x/").Handler(... http.Dir("./x/") ...)`
        statics.each do |sp|
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
                # mux's `.Queries("type", "{type}", ...)` declares
                # required query params; bind them to the endpoint.
                route.query_params.each do |qp|
                  new_endpoint.params << Param.new(qp, "", "query")
                end
                if entries = callees_by_route[route.line]?
                  entries.each do |entry|
                    name, callee_path, callee_line = entry
                    new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end
                new_endpoint.handler = named.handler_for(route)
                new_endpoint.resolution = named.resolution_for(route)
                params_by_route[route.line]?.try &.each { |param| add_param_to_endpoint(param, new_endpoint) }
                named.handler_body(route).try do |body|
                  Noir::GoRequestParamExtractor.params_for_body(body, verb, resolver).each { |param| add_param_to_endpoint(param, new_endpoint) }
                end
                result << new_endpoint
                named.bind(route, new_endpoint)
                last_endpoint = new_endpoint
              end
            end
          end

          add_mux_param_patterns(line, last_endpoint)
        end

        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named,
          group_method: "Subrouter", handlefunc_methods: true, string_seed: string_seed) do |line, ep|
          add_mux_param_patterns(line, ep)
        end

        named.each_attribution { |line, ep| add_mux_param_patterns(line, ep) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    # `mux.Vars(r)["id"]`, then the stdlib request reads.
    private def add_mux_param_patterns(line : String, ep : Endpoint)
      line.scan(/Vars\([^)]+\)\s*\[\s*["']([^"']+)["']\s*\]/) { |m| add_param_to_endpoint(Param.new(m[1], "", "path"), ep) }
      add_request_line_params(line, ep)
    end
  end
end
