require "../../engines/go_engine"

module Analyzer::Go
  class Hertz < GoEngine
    analyzer_for "go_hertz"

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
    BUILDER_TYPE          = "*route.RouterGroup"

    def analyze
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      package_function_bodies = collect_package_function_bodies(file_contents)
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      # `RegisterUsers(h.Group("/api/v1"))` + `func RegisterUsers(g *route.RouterGroup)`:
      # the prefix lives at the call site (see `resolve_router_builder_prefixes`).
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

        named = Noir::GoNamedHandler.new(content, path, ts_routes)
        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups)
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

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
          # Expanded router-builder bodies are emitted below with their
          # call-site prefix.
          next if suppress_ranges.any?(&.includes?(index))
          next if named.claim?(index, line)

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
                  named.bind(route, new_endpoint)
                  last_endpoint = new_endpoint
                end
              else
                new_endpoint = Endpoint.new(route.path, route.verb, details)
                callee_entries.try &.each do |entry|
                  name, callee_path, callee_line = entry
                  new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                end
                named.bind(route, new_endpoint)
                result << new_endpoint
                last_endpoint = new_endpoint
              end
            end
          end

          add_hertz_param_patterns(line, last_endpoint)
        end

        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named, "Handle") do |line, ep|
          add_hertz_param_patterns(line, ep)
        end

        named.each_attribution { |line, ep| add_hertz_param_patterns(line, ep) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    private def add_hertz_param_patterns(line : String, ep : Endpoint)
      # Bind* helpers already contribute a single generic body
      # param below. Skip the accessor loop on those lines so
      # `BindQuery(&input)` does not also fabricate a bogus
      # query param named "&input" via the `Query(` substring.
      is_bind_line = line.matches?(/\.Bind(?:JSON|Query|Header|Form|Protobuf|And\w+)?\s*\(/)

      unless is_bind_line
        ["Query", "PostForm", "GetHeader", "Param", "FormValue"].each do |pattern|
          if line.includes?("#{pattern}(")
            add_param_to_endpoint(get_param(line), ep)
          end
        end
      end

      # Read cookies via `ctx.Cookie("name")`. The leading `\.` avoids matching
      # `SetCookie(...)` (which is for *writing* cookies, not extracting params).
      if line.includes?("Cookie(")
        if cookie_match = line.match(/\.Cookie\s*\(\s*"([^"]+)"/)
          add_param_to_endpoint(Param.new(cookie_match[1], "", "cookie"), ep)
        end
      end

      # Hertz body-binding helpers populate the request
      # body from JSON/form/etc. Surface a single "body"
      # indicator — the bound struct's fields are not
      # statically resolvable here. `And\w+` catches
      # `BindAndValidate`.
      if is_bind_line
        add_param_to_endpoint(Param.new("body", "", "json"), ep)
      end
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
