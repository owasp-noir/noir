require "../../engines/go_engine"
require "../../../miniparsers/go_struct_fields"

module Analyzer::Go
  class Echo < GoEngine
    analyzer_for "go_echo"

    IMPORT_MARKER = "github.com/labstack/echo"
    BUILDER_TYPE  = "*echo.Group"

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
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      # `RegisterUsers(e.Group("/api/v1"))` + `func RegisterUsers(g *echo.Group)`:
      # the prefix lives at the call site (see `resolve_router_builder_prefixes`).
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      named_scope = named_handler_scope(file_contents)
      struct_index = Noir::GoStructFields::Index.new(file_contents, named_scope.import_dirs)
      binders = binder_methods(file_contents)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
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
          handle_many_methods: ["Match"],
          string_seed: string_seed,
          literal_join: true
        )
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        # Echo takes `GET(path, h, m...)`: the handler comes first.
        named = Noir::GoNamedHandler.new(content, path, ts_routes, named_scope, handler_first: true)
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
                new_endpoint.handler = named.handler_for(route)
                result << new_endpoint
                named.bind(route, new_endpoint)
                last_endpoints << new_endpoint
              end
            end
          end

          last_endpoints.each { |ep| add_echo_param_patterns(line, ep) }
        end

        expand_router_builders(content, lines, path, expand_builders, callees_by_route, named, "Add", string_seed: string_seed, literal_join: true) do |line, ep|
          add_echo_param_patterns(line, ep)
        end

        # A named handler's body: `c.Bind(&req)` read as the fields of
        # `req`'s struct, the generic body marker kept only when a bind
        # target does not resolve.
        named.each_bound_body do |file, body_lines, eps|
          fields, unresolved = bind_fields(body_lines, file, struct_index, binders)
          body_lines.each { |line| eps.each { |ep| add_echo_param_patterns(line, ep, bind_marker: unresolved) } }
          eps.each { |ep| add_bind_params(fields, ep) }
        end
      end

      resolve_public_dirs(public_dirs)

      result
    end

    private def add_echo_param_patterns(line : String, ep : Endpoint, bind_marker : Bool = true)
      if line.includes?("Param(") || line.includes?("FormValue(")
        # Every accessor on the line (`f(c.QueryParam("a"), c.QueryParam("b"))`).
        line.scan(ACCESSOR_RE) do |m|
          param = Param.new(m[2].gsub("\"", "").strip, "", ACCESSOR_TYPES[m[1]])
          # `FormValue` is net/http's: the body is parsed only for POST, PUT
          # and PATCH, so on any other method it reads the query string.
          param.param_type = "query" if param.param_type == "form" && !FORM_BODY_METHODS.includes?(ep.method)
          # A shared helper may read a path variable this route has no slot for.
          if param.param_type != "path" || ep.url.includes?(param.name == "*" ? "*" : ":#{param.name}")
            add_param_to_endpoint(param, ep)
          end
        end
      end
      # `c.QueryParams().Get("from")`, `c.Request().URL.Query()["id"]`.
      Noir::GoRequestParamExtractor.query_params(line).each { |param| add_param_to_endpoint(param, ep) }

      # `c.Bind(&v)` / `c.BindBody(...)` populate the request body. Echo
      # also exposes `BindJSON`-style helpers via the echo-contrib package.
      # A single "body" indicator, unless the caller read the bound
      # struct's fields instead (`bind_marker` false, see `bind_fields`).
      if bind_marker && line.matches?(BIND_ANY) &&
         !line.includes?("// ")
        add_param_to_endpoint(Param.new("body", "", "json"), ep)
      end

      Noir::GoRequestParamExtractor.header_params(line).each { |header| add_param_to_endpoint(header, ep) }

      if line.includes?("Cookie(") &&
         !line.includes?("Header.Get") && !line.includes?("Query().Get") &&
         !line.includes?("Request().Header.Get")
        match = line.match(/Cookie\(\s*\"(.*)\"\s*\)/)
        if match
          ep.params << Param.new(match[1], "", "cookie")
        end
      end
    end

    FORM_BODY_METHODS = %w[POST PUT PATCH]

    BIND_ANY = /\.Bind(?:Body|JSON|XML|YAML|Headers|Query|Path)?\s*\(/
    # `c.Bind(&req)`, or `c.Bind(req)` with `req` already a pointer: Echo's DefaultBinder.
    BIND_CALL = /\.Bind\s*\(\s*&?\s*([A-Za-z_]\w*)\s*\)/
    # `func (r *loginRequest) bind(c echo.Context, ...) error {`: a method that may bind its receiver.
    # `func (r *loginRequest) bind(...)`: the receiver name and type of a method declaration.
    METHOD_RECEIVER = /\Afunc\s*\(\s*(\w+)\s+\*?(\w+)\s*\)/
    METHOD_CALL     = /\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(/

    # `{method name => receiver types}` of methods whose body binds their
    # own receiver (`return c.Bind(r)` in `func (r *loginRequest) bind(c
    # echo.Context)`), so a handler's `req.bind(c)` reads as a bind of `req`
    # when `req` is one of those types. Bodies come from the shared
    # tree-sitter method table.
    private def binder_methods(file_contents : Hash(String, String)) : Hash(String, Set(String))
      binders = Hash(String, Set(String)).new
      file_contents.each do |path, content|
        next unless content.includes?(".Bind(")
        Noir::GoCalleeExtractor.collect_method_bodies(content, path).each do |name, bodies|
          bodies.each do |body|
            next unless m = body.source.match(METHOD_RECEIVER)
            receiver, type_name = m[1], m[2]
            if body.source.scan(BIND_CALL).any? { |bind| bind[1] == receiver }
              (binders[name] ||= Set(String).new) << type_name
            end
          end
        end
      end
      binders
    end

    # The bare type name a body declares `name` with (`req := &loginRequest{}`).
    private def declared_type_name(lines : Array(String), name : String) : String?
      lines.each do |line|
        m = line.match(Noir::GoStructFields::Index::DECLARED_TYPE) || line.match(Noir::GoStructFields::Index::ASSIGNED_TYPE)
        return m[2].rpartition('.').last if m && m[1] == name
      end
      nil
    end

    # The fields the binds in `lines` fill, and whether any bind target did
    # not resolve to a struct.
    private def bind_fields(lines : Array(String), file : String, index : Noir::GoStructFields::Index,
                            binders : Hash(String, Set(String)) = Hash(String, Set(String)).new) : Tuple(Array(Noir::GoStructFields::Field), Bool)
      fields = [] of Noir::GoStructFields::Field
      unresolved = false
      lines.each do |line|
        # `{target, direct}`: a `.Bind(...)` call, or a call of a binder
        # method on the target (`req.bind(c)`), which adds no marker when
        # the target does not resolve.
        targets = [] of Tuple(String, Bool)
        unless binders.empty?
          line.scan(METHOD_CALL) do |m|
            types = binders[m[2]]?
            targets << {m[1], false} if types && (type_name = declared_type_name(lines, m[1])) && types.includes?(type_name)
          end
        end
        if line.includes?(".Bind")
          # A bind variant this does not read (`BindHeaders`, `Bind(x.y)`).
          unresolved = true if line.matches?(BIND_ANY) && !line.matches?(BIND_CALL)
          line.scan(BIND_CALL) { |m| targets << {m[1], true} }
        end
        targets.each do |target, direct|
          found = index.target_fields(lines, target, file)
          # A struct with no bindable tag (`struct{ Food string }` binds
          # JSON by field name) keeps the generic marker.
          if found && found.any? { |f| BIND_TAGS.any? { |key| Noir::GoStructFields.tag_value(f.tag, key) } }
            fields.concat(found)
          elsif direct
            unresolved = true
          end
        end
      end
      {fields, unresolved}
    end

    # Echo's DefaultBinder: `param` tags from the path, `query` tags on GET,
    # DELETE and HEAD, then the body by Content-Type: `json` tags and `form`
    # tags (either encoding may be sent, so both are listed). GET and HEAD
    # carry no body. Untagged fields are left out.
    private def add_bind_params(fields : Array(Noir::GoStructFields::Field), ep : Endpoint)
      fields.each do |field|
        if (name = Noir::GoStructFields.tag_value(field.tag, "param")) && ep.url.includes?(":#{name}")
          add_param_to_endpoint(Param.new(name, "", "path"), ep)
        end
        if QUERY_BIND_METHODS.includes?(ep.method) && (name = Noir::GoStructFields.tag_value(field.tag, "query"))
          add_param_to_endpoint(Param.new(name, "", "query"), ep)
        end
        next if NO_BODY_METHODS.includes?(ep.method)
        Noir::GoStructFields.tag_value(field.tag, "json").try { |json| add_param_to_endpoint(Param.new(json, "", "json"), ep) }
        Noir::GoStructFields.tag_value(field.tag, "form").try { |form| add_param_to_endpoint(Param.new(form, "", "form"), ep) }
      end
    end

    BIND_TAGS          = %w[param query json form]
    QUERY_BIND_METHODS = %w[GET DELETE HEAD]
    NO_BODY_METHODS    = %w[GET HEAD]

    ACCESSOR_RE    = /\b(QueryParam|FormValue|Param)\s*\(([^()]*)\)/
    ACCESSOR_TYPES = {"QueryParam" => "query", "FormValue" => "form", "Param" => "path"}

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
