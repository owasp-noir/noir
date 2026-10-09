require "../../engines/go_engine"

module Analyzer::Go
  class Gin < GoEngine
    analyzer_for "go_gin"

    IMPORT_MARKER = "github.com/gin-gonic/gin"
    BUILDER_TYPE  = "*gin.RouterGroup"

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
      # Cross-file router-builder prefix resolution: `{dir => {builder_fn
      # => set(call-site prefixes)}}`. Resolves the canonical gin layout
      # where `func addXRoutes(rg *gin.RouterGroup)` helpers are called
      # from a central function with a versioned group (`addUserRoutes(
      # router.Group("/v1"))`). The prefix lives at the call site, so it
      # must be grafted onto the helper's routes.
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if GoEngine.go_test_file?(base_relative_path(path))
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Handle", "Static"])
        lines = content.lines
        last_endpoint = Endpoint.new("", "")

        # Tree-sitter pre-pass: harvest every verb route with its
        # group-resolved path in one go. Indexed by line so the
        # line loop below can attribute body params (Query/PostForm
        # /GetHeader/Cookie) to the most recently declared route —
        # matching the legacy `last_endpoint` semantics.
        cross_file_groups = ts_groups_for_directory(package_groups, dir)

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
        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups)
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

        # Gin also accepts `r.Handle(method, path, handler)`
        # alongside the verb shortcuts (`r.GET`, etc.),
        # so opt into the method-first decoder so those
        # registrations surface as endpoints too.
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Handle")
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        named = Noir::GoNamedHandler.new(content, path, ts_routes)

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
                result << new_endpoint
                named.bind(route, new_endpoint)
                last_endpoint = new_endpoint
              end
            end
          end

          add_gin_param_patterns(line, last_endpoint)
        end

        # Expansion pass: emit each suppressed router-builder's
        # routes once per resolved call-site prefix, with the
        # group parameter bound to that prefix. (A helper called
        # from two versioned groups — `addPingRoutes(v1)` and
        # `addPingRoutes(v2)` — yields both `/v1/ping` and
        # `/v2/ping`.)
        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named, "Handle") do |line, ep|
          add_gin_param_patterns(line, ep)
        end

        named.each_attribution { |line, ep| add_gin_param_patterns(line, ep) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    private def add_gin_param_patterns(line : String, target : Endpoint)
      # Bind*/ShouldBind* already contribute a single generic body param.
      # Skip the accessor loop on those lines so `ShouldBindQuery(&x)` does
      # not also fabricate a bogus query param named "&x".
      is_bind_line = line.matches?(/\.(?:Should)?Bind(?:JSON|XML|YAML|TOML|Query|Header|Uri|With)?\s*\(/)

      unless is_bind_line
        ["Query", "PostForm", "GetHeader", "Param"].each do |pattern|
          if line.includes?("#{pattern}(")
            add_param_to_endpoint(get_param(line), target)
          end
        end
      end
      if is_bind_line
        add_param_to_endpoint(Param.new("body", "", "json"), target)
      end
      # Read accessor only: `.Cookie("name")`. The `.Cookie(` anchor excludes
      # Header.Get/Cookie.Get; the SetCookie exclusion avoids the write API.
      if line.includes?(".Cookie(") && !line.includes?("SetCookie(")
        match = line.match(/\.Cookie\s*\(\s*"([^"]*)"/)
        if match
          target.params << Param.new(match[1], "", "cookie")
        end
      end
    end

    def get_param(line : String) : Param
      param_type = "json"
      if line.includes?("Query(")
        param_type = "query"
      end
      if line.includes?("PostForm(")
        param_type = "form"
      end
      if line.includes?("GetHeader(")
        param_type = "header"
      end
      # `c.Param("id")` — Gin path variable accessor. The optimizer
      # also derives `:id` path params from the URL pattern, but
      # surfacing the accessor lets us catch handlers whose route
      # path was resolved cross-file and avoids depending on the
      # optimizer pass for direct-analyzer consumers.
      if line.includes?(".Param(")
        param_type = "path"
      end

      # Capture only the accessor's first string-literal argument. Naive
      # split("(")/split(")") desyncs when DefaultQuery/DefaultPostForm's
      # default-value argument contains nested calls (e.g. strconv.Itoa(n)).
      if match = line.match(/(?:Query|PostForm|GetHeader|Param)\s*\(\s*"([^"]*)"/)
        return Param.new(match[1], "", param_type)
      end

      Param.new("", "", "")
    end
  end
end
