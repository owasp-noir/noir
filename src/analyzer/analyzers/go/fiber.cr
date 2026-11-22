require "../../engines/go_engine"

module Analyzer::Go
  class Fiber < GoEngine
    analyzer_for "go_fiber"

    IMPORT_MARKER = "github.com/gofiber/fiber"
    BUILDER_TYPE  = "fiber.Router"
    # Struct field types that hold a router (`s.app.Get(...)`).
    ROUTER_TYPES = {IMPORT_MARKER => %w[App Router Group]}

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
      # `func RegisterAdmin(admin *svr.Admin)` with `type Admin struct {
      # fiber.Router }` built once from a group: the prefix comes with the type.
      wrappers = resolve_router_wrappers(file_contents, BUILDER_TYPE)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      named_scope = named_handler_scope(file_contents)
      router_fields = package_router_fields(file_contents, ROUTER_TYPES, named_scope.import_dirs, package_groups)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Add", "Static"])
        lines = GoEngine.strip_comments(content).lines
        last_endpoint = Endpoint.new("", "")

        # Tree-sitter pre-pass for Fiber's verb-method routes.
        # websocket.New(...) detection stays on the raw line text
        # because it's a sibling expression, not part of the route
        # argument list.
        receivers, cross_file_groups = file_router_receivers(router_fields, path, content, ts_groups_for_directory(package_groups, dir))
        # `app.Route("/r", func(r fiber.Router){...})` scopes a prefix to
        # the closure; `app.Mount("/mnt", micro)` prefixes a sub-app.
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
          content, cross_file_groups, handle_method: "Add",
          closure_group_methods: ["Route"], mount_methods: ["Mount"],
          router_fields: receivers)
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        named = go_named_handler(content, path, ts_routes, named_scope)
        expand_builders = router_builder_expansions(content, BUILDER_TYPE, builder_prefixes_by_dir[dir]?, cross_file_groups)
        expand_builders += router_wrapper_expansions(content, path, wrappers, expand_builders) unless wrappers.empty?
        suppress_ranges = expand_builders.map { |_, rb, _| rb.start_row..rb.end_row }

        # Resolve 1-hop callees for every route (see Gin).
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

        # `app.Static("/url", "./dir")`.
        Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
          public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
        end

        # The lines credited to `last_endpoint` since its route, read as one
        # body when the next route starts (or the file ends).
        segment = [] of String
        each_route_line(lines, routes_by_line) do |line, index, ts_hits|
          # Expanded router-builder bodies are emitted below with their
          # call-site prefix.
          next if suppress_ranges.any?(&.includes?(index))
          next if named.claim?(index, line)

          if ts_hits
            add_fiber_body_params(segment, path, [last_endpoint], named_scope.structs)
            segment = [] of String
            ts_hits.each do |route|
              details = go_route_details(route, path, content)
              Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                new_endpoint = Endpoint.new(route.path, verb, details)
                new_endpoint.protocol = "ws" if route.handler.includes?("websocket.New(")
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
                last_endpoint = new_endpoint
              end
            end
          end

          segment << line
        end
        add_fiber_body_params(segment, path, [last_endpoint], named_scope.structs)

        expand_router_builders(content, path, expand_builders, callees_by_route, named, "Add") do |line, ep|
          add_fiber_param_patterns(line, ep)
        end

        named.each_bound_body { |file, body_lines, eps| add_fiber_body_params(body_lines, file, eps, named_scope.structs) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    REQUEST_HEADER_GET_RE = /\b(?:c|ctx)\.Get\(\s*"([^"]+)"/

    # The context's readers, every one on the line: `Query` and its typed
    # forms, `FormValue`, `FormFile`, `Params` / `ParamsInt`.
    ACCESSOR_RE = /\.(Query(?:Int|Bool|Float)?|FormValue|FormFile|Params(?:Int)?)\s*\(\s*"([^"]*)"/

    # Fiber's struct parsers (`c.QueryParser(&f)`) and the tags each fills
    # from, by param type. `BodyParser` takes `json` or `form` by
    # Content-Type, so both are listed.
    PARSER_CALL = /\.(BodyParser|QueryParser|ReqHeaderParser|ParamsParser|CookieParser)\s*\(\s*&?\s*([A-Za-z_]\w*)\s*\)/
    PARSER_TAGS = {
      "BodyParser"      => {"json" => "json", "form" => "form"},
      "QueryParser"     => {"query" => "query"},
      "ReqHeaderParser" => {"reqHeader" => "header"},
      "ParamsParser"    => {"params" => "path"},
      "CookieParser"    => {"cookie" => "cookie"},
    }

    # Lines that belong to one route (an inline closure's body, or a named
    # handler's): a parser call read as the tagged fields of its target's
    # struct, the generic body marker kept only for a `BodyParser` whose
    # target does not resolve.
    private def add_fiber_body_params(lines : Array(String), file : String, eps : Array(Endpoint), index : Noir::GoStructFields::Index)
      found = [] of Param
      unresolved = false
      lines.each do |line|
        next unless line.includes?("Parser(")
        body_read = false
        line.scan(PARSER_CALL) do |m|
          fields = index.target_fields(lines, m[2], file) || next
          params = fields.flat_map do |field|
            PARSER_TAGS[m[1]].compact_map { |tag, type| Noir::GoStructFields.tag_value(field.tag, tag).try { |name| Param.new(name, "", type) } }
          end
          found.concat(params)
          body_read = true if m[1] == "BodyParser" && !params.empty?
        end
        unresolved = true if line.includes?(".BodyParser(") && !body_read
      end
      lines.each { |line| eps.each { |ep| add_fiber_param_patterns(line, ep, body_marker: unresolved) } }
      eps.each { |ep| found.each { |param| add_param_to_endpoint(param, ep) } }
    end

    private def add_fiber_param_patterns(line : String, ep : Endpoint, body_marker : Bool = true)
      line.scan(ACCESSOR_RE) do |m|
        # `app.Query("/search", h)` is a registration, not a read.
        next if m[2].starts_with?("/")
        type = if m[1].starts_with?("Query")
                 "query"
               elsif m[1].starts_with?("Params")
                 "path"
               else
                 "form"
               end
        add_param_to_endpoint(Param.new(m[2], "", type), ep)
      end

      if body_marker && line.includes?(".BodyParser(")
        add_param_to_endpoint(Param.new("body", "", "json"), ep)
      end

      # `c.Get("X-Api-Key")` reads a request header (`GetRespHeader` and
      # `Vary` act on the response, so they are not request params). The
      # context receiver is pinned to the conventional names so a cache or
      # config `Get` is not read as a header; a path literal is a route
      # registration (`app.Get("/x", h)`).
      if line.includes?(".Get(") && (match = line.match(REQUEST_HEADER_GET_RE)) && !match[1].starts_with?("/")
        add_param_to_endpoint(Param.new(match[1], "", "header"), ep)
      end

      # `c.Cookies("session")`, `c.Cookies("session", "none")`.
      if line.includes?("Cookies(") &&
         !line.includes?("Header.Get") && !line.includes?("Cookie.Get")
        line.scan(/Cookies\(\s*"([^"]*)"/) { |m| add_param_to_endpoint(Param.new(m[1], "", "cookie"), ep) }
      end
    end
  end
end
