require "../../engines/go_engine"

module Analyzer::Go
  class Gin < GoEngine
    analyzer_for "go_gin"

    IMPORT_MARKER = "github.com/gin-gonic/gin"
    BUILDER_TYPE  = "*gin.RouterGroup"
    # Helper parameter types a group is handed as; the interfaces also take
    # the engine, and a helper handed it anywhere is not expanded.
    BUILDER_TYPES = [BUILDER_TYPE, "gin.IRouter", "gin.IRoutes"]
    # Struct field types that hold a router (`s.router.GET(...)`).
    ROUTER_TYPES = {IMPORT_MARKER => %w[Engine RouterGroup IRouter IRoutes]}

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Paths built through constants of other packages and wrapper calls
      # (`router.Group(conf.BaseUri(config.ApiUri))`).
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
      # Cross-file router-builder prefix resolution: `{dir => {builder_fn
      # => set(call-site prefixes)}}`. Resolves the canonical gin layout
      # where `func addXRoutes(rg *gin.RouterGroup)` helpers are called
      # from a central function with a versioned group (`addUserRoutes(
      # router.Group("/v1"))`). The prefix lives at the call site, so it
      # must be grafted onto the helper's routes.
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPES)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      named_scope = named_handler_scope(file_contents, infer_module: true)
      resolver = Noir::GoRequestParamExtractor::Resolver.new(named_scope.bodies, file_contents, named_scope.import_dirs, "gin", named_scope.structs)
      router_fields = package_router_fields(file_contents, ROUTER_TYPES, named_scope.import_dirs, package_groups)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Handle", "Static"])
        lines = GoEngine.strip_comments(content).lines
        last_endpoints = [] of Endpoint

        # Tree-sitter pre-pass: harvest every verb route with its
        # group-resolved path in one go. Indexed by line so the
        # line loop below can attribute body params (Query/PostForm
        # /GetHeader/Cookie) to the most recently declared route —
        # matching the legacy `last_endpoint` semantics.
        receivers, cross_file_groups = file_router_receivers(router_fields, path, content, ts_groups_for_directory(package_groups, dir))

        # Router-builder expansion: graft call-site prefixes onto
        # the routes of `func addXRoutes(rg *gin.RouterGroup)`
        # helpers DEFINED in this file. Only "case b" helpers are
        # expanded — those whose group parameter name is NOT
        # already a key in the package group map. ("Case a" helpers
        # whose parameter name happens to match a caller's group
        # variable, e.g. both named `v1`, are already resolved by
        # the whole-file pass below, so they're left untouched to
        # keep their params/callees.) Expanded helpers' bodies are
        # suppressed in the whole-file pass to avoid emitting the
        # prefix-less variant alongside the corrected one.
        expand_builders = router_builder_expansions(content, BUILDER_TYPES, builder_prefixes_by_dir[dir]?, cross_file_groups)
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

        # Gin also accepts `r.Handle(method, path, handler)` and
        # `r.Match([]string{"GET", "HEAD"}, path, handler)` alongside the
        # verb shortcuts (`r.GET`, etc.), so opt into the method-first
        # decoders so those registrations surface as endpoints too.
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Handle",
          handle_many_methods: ["Match"], string_seed: string_seed, router_fields: receivers)
        # A helper's routes on a group no call site gave a readable prefix (#3567).
        unread = unread_builder_routes(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups, "Handle", string_seed)
        ts_routes.map! { |r| unread.includes?({r.line, r.path}) ? r.unresolve_prefix! : r } unless unread.empty?
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        named = Noir::GoNamedHandler.new(content, path, ts_routes, named_scope)

        # Resolve 1-hop callees for every route in this file.
        # Inline-closure handlers walk in place; bare
        # identifier handlers fall through to sibling-file
        # function bodies via the per-directory map.
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

        # Gin uses `r.Static("/url", "./dir")`. Pick these up
        # in a single tree-sitter pass up front; downstream
        # `resolve_public_dirs` still expects the legacy hash
        # shape, so we convert here.
        Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
          public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
        end

        # StaticFile / StaticFileFS register a single file URL —
        # emit the route directly. Do not feed them through
        # resolve_public_dirs (directory glob), which drops "/"
        # prefixes and skips common media extensions like .ico.
        ["StaticFile", "StaticFileFS"].each do |mn|
          Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content, method_name: mn).each do |sp|
            sf_details = Details.new(PathInfo.new(path, sp.line + 1))
            result << Endpoint.new(sp.url_prefix, "GET", sf_details)
          end
        end

        # The lines credited to `last_endpoint` since their route, read as one
        # body when the next route starts (or the file ends).
        segment = [] of String
        lines.each_with_index do |line, index|
          # Skip lines inside an expanded router-builder body — its
          # routes (and any params) are emitted, with the call-site
          # prefix applied, by the expansion pass below.
          next if suppress_ranges.any?(&.includes?(index))
          # A named handler's body belongs to the route that names it.
          next if named.claim?(index, line)

          details = Details.new(PathInfo.new(path, index + 1))

          # Emit endpoints for any verb route that begins on this
          # line. Gin allows the same verb method name upper/lower
          # (`r.GET` vs `r.Get`); both are covered by the TS
          # extractor's HTTP_VERB_METHODS set.
          if ts_hits = routes_by_line[index]?
            add_gin_body_params(segment, path, last_endpoints, resolver)
            segment = [] of String
            last_endpoints = [] of Endpoint
            ts_hits.each do |route|
              # `r.Any(...)` / `r.All(...)` register one route under
              # every HTTP method. Fan out so downstream formats
              # (SARIF / Postman / openapi) get a usable verb per
              # endpoint instead of a non-HTTP "ANY" string they
              # can't ingest.
              Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                new_endpoint = Endpoint.new(route.path, verb, details)
                if entries = callees_by_route[route.line]?
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
        add_gin_body_params(segment, path, last_endpoints, resolver)

        # Expansion pass: emit each suppressed router-builder's
        # routes once per resolved call-site prefix, with the
        # group parameter bound to that prefix. (A helper called
        # from two versioned groups — `addPingRoutes(v1)` and
        # `addPingRoutes(v2)` — yields both `/v1/ping` and
        # `/v2/ping`.)
        # Each expanded endpoint's lines are read as one body (keyed by its
        # params array, which every copy of the struct shares).
        builder_bodies = Hash(UInt64, Tuple(Endpoint, Array(String))).new
        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named, "Handle", string_seed: string_seed) do |line, ep|
          (builder_bodies[ep.params.object_id] ||= {ep, [] of String})[1] << line
        end
        builder_bodies.each_value { |(ep, body_lines)| add_gin_body_params(body_lines, path, [ep], resolver) }

        named.each_attribution { |line, ep| add_gin_param_patterns(line, ep) }
        named.each_bound_body(direct_only: true) { |file, body_lines, eps| add_binding_params(body_lines, file, eps, resolver) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    private def add_gin_body_params(lines, file, eps, resolver)
      lines.each { |line| eps.each { |ep| add_gin_param_patterns(line, ep) } }
      add_binding_params(lines, file, eps, resolver)
    end

    private def add_gin_param_patterns(line : String, target : Endpoint)
      line.scan(ACCESSOR_RE) { |m| add_param_to_endpoint(Param.new(m[2], "", accessor_type(m[1])), target) }
      # `c.Cookie("name")`, and the stdlib request behind the context
      # (`c.Request.URL.Query().Get("q")`, `c.Request.Header.Get("X")`).
      Noir::GoRequestParamExtractor.line_params(line, target.method).each { |param| add_param_to_endpoint(param, target) }
    end

    # The context's readers, every one on the line: `Query` with its
    # `Default` / `Get` / `Array` / `Map` forms, the same `PostForm` family,
    # `FormFile`, `GetHeader` and `Param`.
    ACCESSOR_RE = /\.((?:Default|Get)?Query(?:Array|Map)?|(?:Default|Get)?PostForm(?:Array|Map)?|FormFile|GetHeader|Param)\s*\(\s*"([^"]*)"/

    private def accessor_type(accessor : String) : String
      if accessor.includes?("Query")
        "query"
      elsif accessor == "GetHeader"
        "header"
      elsif accessor == "Param"
        "path"
      else
        "form"
      end
    end
  end
end
