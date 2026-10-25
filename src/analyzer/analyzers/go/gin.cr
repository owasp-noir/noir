require "../../engines/go_engine"
require "../../../miniparsers/go_struct_fields"

module Analyzer::Go
  class Gin < GoEngine
    analyzer_for "go_gin"

    IMPORT_MARKER = "github.com/gin-gonic/gin"
    BUILDER_TYPE  = "*gin.RouterGroup"

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
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      # Cross-file router-builder prefix resolution: `{dir => {builder_fn
      # => set(call-site prefixes)}}`. Resolves the canonical gin layout
      # where `func addXRoutes(rg *gin.RouterGroup)` helpers are called
      # from a central function with a versioned group (`addUserRoutes(
      # router.Group("/v1"))`). The prefix lives at the call site, so it
      # must be grafted onto the helper's routes.
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups, BUILDER_TYPE)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      named_scope = named_handler_scope(file_contents)
      struct_index = Noir::GoStructFields::Index.new(file_contents, named_scope.import_dirs)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if GoEngine.go_test_file?(base_relative_path(path))
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Handle", "Static"])
        lines = GoEngine.strip_comments(content).lines
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

        # Gin also accepts `r.Handle(method, path, handler)` and
        # `r.Match([]string{"GET", "HEAD"}, path, handler)` alongside the
        # verb shortcuts (`r.GET`, etc.), so opt into the method-first
        # decoders so those registrations surface as endpoints too.
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Handle",
          handle_many_methods: ["Match"], string_seed: string_seed)
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

        # The lines credited to `last_endpoint` since its route, read as one
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
            add_gin_body_params(segment, path, [last_endpoint], struct_index)
            segment = [] of String
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
                result << new_endpoint
                named.bind(route, new_endpoint)
                last_endpoint = new_endpoint
              end
            end
          end

          segment << line
        end
        add_gin_body_params(segment, path, [last_endpoint], struct_index)

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
        builder_bodies.each_value { |(ep, body_lines)| add_gin_body_params(body_lines, path, [ep], struct_index) }

        named.each_bound_body { |file, body_lines, eps| add_gin_body_params(body_lines, file, eps, struct_index) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    # Lines that belong to one route (an inline closure's body, or a named
    # handler's): `c.ShouldBind(&req)` read as the fields of `req`'s struct,
    # the generic body marker kept only when a bind target does not resolve.
    private def add_gin_body_params(lines : Array(String), file : String, eps : Array(Endpoint), index : Noir::GoStructFields::Index)
      binds, unresolved = gin_bind_fields(lines, file, index)
      lines.each { |line| eps.each { |ep| add_gin_param_patterns(line, ep, bind_marker: unresolved) } }
      eps.each { |ep| binds.each { |kind, fields| add_gin_bind_params(kind, fields, ep) } }
    end

    BIND_LINE = /\.(?:Must|Should)?Bind(?:JSON|XML|YAML|TOML|Query|Header|Uri|With|BodyWith|BodyWithJSON)?\s*\(/
    # `c.ShouldBindJSON(&req)`, `c.MustBindWith(params, binding.Query)`.
    BIND_CALL = /\.(?:Must|Should)?Bind(JSON|Query|Header|Uri|With|BodyWith|BodyWithJSON)?\s*\(\s*&?\s*([A-Za-z_]\w*)\s*(?:,\s*binding\.(\w+)\s*)?\)/
    # The binder a `binding.X` argument names.
    BINDING_KINDS = {"JSON" => "json", "Query" => "query", "Form" => "form", "FormPost" => "form",
                     "FormMultipart" => "form", "Uri" => "uri", "Header" => "header"}
    # The struct tags each binder reads.
    BIND_KIND_TAGS = {"default" => %w[json form], "json" => %w[json], "query" => %w[form],
                      "form" => %w[form], "uri" => %w[uri], "header" => %w[header]}

    # The binds in `lines` as {binder, fields}, and whether any bind did not
    # resolve to tagged struct fields.
    private def gin_bind_fields(lines : Array(String), file : String, index : Noir::GoStructFields::Index) : Tuple(Array(Tuple(String, Array(Noir::GoStructFields::Field))), Bool)
      binds = [] of Tuple(String, Array(Noir::GoStructFields::Field))
      unresolved = false
      lines.each do |line|
        next unless line.includes?("Bind")
        next unless line.matches?(BIND_LINE)
        match = line.match(BIND_CALL)
        kind = match.try { |m| gin_bind_kind(m[1]?, m[3]?) }
        fields = kind && match && index.target_fields(lines, match[2], file)
        # A struct with no tag its binder reads keeps the generic marker.
        if kind && fields && fields.any? { |f| BIND_KIND_TAGS[kind].any? { |key| Noir::GoStructFields.tag_value(f.tag, key) } }
          binds << {kind, fields}
        else
          unresolved = true
        end
      end
      {binds, unresolved}
    end

    # `Bind`/`ShouldBind` pick the binder from the method and Content-Type;
    # the suffixed forms and `binding.X` name it. Nil for one not read here
    # (XML, YAML, TOML, ProtoBuf).
    private def gin_bind_kind(suffix : String?, binding : String?) : String?
      case suffix
      when nil                    then "default"
      when "JSON", "BodyWithJSON" then "json"
      when "Query"                then "query"
      when "Header"               then "header"
      when "Uri"                  then "uri"
      else                             binding.try { |b| BINDING_KINDS[b]? }
      end
    end

    # gin's binders: the default one reads the query string (`form` tags) on
    # GET, otherwise the body by Content-Type, `json` or `form` tags (either
    # encoding may be sent, so both are listed). `uri` tags fill path slots,
    # `header` tags headers. Untagged and `-` fields are left out.
    private def add_gin_bind_params(kind : String, fields : Array(Noir::GoStructFields::Field), ep : Endpoint)
      fields.each do |field|
        case kind
        when "uri"
          if (name = Noir::GoStructFields.tag_value(field.tag, "uri")) && (ep.url.includes?(":#{name}") || ep.url.includes?("*#{name}"))
            add_param_to_endpoint(Param.new(name, "", "path"), ep)
          end
        when "header"
          Noir::GoStructFields.tag_value(field.tag, "header").try { |name| add_param_to_endpoint(Param.new(name, "", "header"), ep) }
        when "query"
          Noir::GoStructFields.tag_value(field.tag, "form").try { |name| add_param_to_endpoint(Param.new(name, "", "query"), ep) }
        else
          query = ep.method == "GET"
          if kind == "json" || (kind == "default" && !query)
            Noir::GoStructFields.tag_value(field.tag, "json").try { |name| add_param_to_endpoint(Param.new(name, "", "json"), ep) }
          end
          if kind != "json"
            Noir::GoStructFields.tag_value(field.tag, "form").try { |name| add_param_to_endpoint(Param.new(name, "", query ? "query" : "form"), ep) }
          end
        end
      end
    end

    private def add_gin_param_patterns(line : String, target : Endpoint, bind_marker : Bool = true)
      # Bind*/ShouldBind* already contribute a single generic body param.
      # Skip the accessor loop on those lines so `ShouldBindQuery(&x)` does
      # not also fabricate a bogus query param named "&x".
      is_bind_line = line.matches?(BIND_LINE)

      unless is_bind_line
        ["Query", "PostForm", "GetHeader", "Param"].each do |pattern|
          if line.includes?("#{pattern}(")
            add_param_to_endpoint(get_param(line), target)
          end
        end
      end
      if is_bind_line && bind_marker
        add_param_to_endpoint(Param.new("body", "", bind_param_type(line)), target)
      end
      # Read accessor only: `.Cookie("name")`. The `.Cookie(` anchor excludes
      # Header.Get/Cookie.Get; the SetCookie exclusion avoids the write API.
      if line.includes?(".Cookie(") && !line.includes?("SetCookie(")
        match = line.match(/\.Cookie\s*\(\s*"([^"]*)"/)
        if match
          target.params << Param.new(match[1], "", "cookie")
        end
      end
      # `c.Request.Header.Get("X")` / `req.Header["X"]`: the stdlib read
      # `c.GetHeader` wraps.
      Noir::GoRequestParamExtractor.header_params(line).each { |header| add_param_to_endpoint(header, target) }
    end

    # Where a bind call reads from: `ShouldBindQuery(&q)` and
    # `ShouldBindWith(&q, binding.Query)` read the query string, not a JSON
    # body; `BindHeader` / `BindUri` the header / path; `binding.Form*` a form.
    private def bind_param_type(line : String) : String
      case line
      when /Bind(?:Query)\s*\(|binding\.Query\b/ then "query"
      when /BindHeader\s*\(|binding\.Header\b/   then "header"
      when /BindUri\s*\(|binding\.Uri\b/         then "path"
      when /binding\.Form(?:Post|Multipart)?\b/  then "form"
      else                                            "json"
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
