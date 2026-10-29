require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"
require "../../../miniparsers/go_struct_fields"

module Analyzer::Go
  class GoZero < GoEngine
    analyzer_for "go_gozero"

    IMPORT_MARKER = "github.com/zeromicro/go-zero"

    # One precompiled matcher instead of a `String#includes?` scan per
    # `.go` file: `includes?` runs Rabin-Karp over the whole buffer and
    # the marker is absent in the overwhelming majority of files in a
    # polyglot repo, so every one of them pays the full scan. See
    # `Analyzer#content_matches?`.
    IMPORT_MARKER_RE = Regex.union(IMPORT_MARKER)

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The accessor set is fixed, so precompile
    # the per-accessor matchers once at load time.
    PARAM_ACCESSOR_PATTERNS = ["Query", "PostForm", "GetHeader", "PathParam", "FormValue"].to_h do |pattern|
      {pattern, /#{Regex.escape(pattern)}\(\s*"([^"]+)"/}
    end

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Pre-pass for cross-file identifier-handler resolution. Only
      # `.go` routes (`server.Get("/x", h)` shape) get callees —
      # gozero's `.api` files are a non-Go DSL that declares routes as
      # `get /path (Request)` with an `@handler Name` directive; there's
      # no Go call_expression to extract a 1-hop graph from.
      # `read_package_file_contents` already filters to `.go`, so the
      # function-body map naturally skips `.api`.
      file_contents = read_package_file_contents
      package_function_bodies = collect_package_function_bodies(file_contents)
      # goctl puts handlers in a subpackage of `routes.go` when the `.api`
      # group sets `group:` (`user.DetailHandler(serverCtx)`).
      import_path_function_bodies = collect_import_path_function_bodies(package_function_bodies)
      named_scope = named_handler_scope(file_contents)
      struct_index = Noir::GoStructFields::Index.new(file_contents, named_scope.import_dirs)
      # Both `.go` files and gozero's `.api` DSL files. The per-path
      # `File.extname` re-check the inlined walk carried is redundant:
      # `get_files_by_extensions` resolves the same `File.extname` index,
      # so every path here already has one of those two extensions.
      parallel_analyze(get_files_by_extensions([".go", ".api"])) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)

        content = read_file_content(path)
        # `.api` files are gozero's DSL (no Go imports);
        # only gate `.go` files on the import marker.
        next if File.extname(path) == ".go" && !content_matches?(content, IMPORT_MARKER_RE)
        lines = GoEngine.strip_comments(content).lines
        last_endpoint = Endpoint.new("", "")

        # Go files: tree-sitter pre-pass (same verb-on-identifier
        # pattern Gin uses, no groups in gozero's common idioms).
        # .api files use a non-Go DSL — keep the legacy regex.
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        callees_by_route = Hash(Int32, Array(Tuple(String, String, Int32))).new
        if File.extname(path) == ".go"
          Noir::TreeSitterGoRouteExtractor.extract_routes(content).each do |r|
            next unless r.raw_path.starts_with?("/")
            routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
            routes_by_line[r.line] << r
          end
          Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
            public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
          end

          # go-zero's canonical generated `routes.go`:
          # `server.AddRoutes([]rest.Route{ {Method, Path,
          # Handler}, ... }, rest.WithPrefix("/p"))`. These are
          # struct literals, not verb calls, so the generic
          # extractor misses them. Fold them into the same
          # per-line map for emission with full mounted paths.
          Noir::TreeSitterGoRouteExtractor.extract_gozero_routes(content).each do |r|
            routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
            routes_by_line[r.line] << r
          end

          # Resolve 1-hop callees for every route, `AddRoutes` rows
          # included: their handler factory lives in this package or, with
          # a goctl `group:`, in an imported one.
          route_rows = Set(Int32).new
          routes_by_line.each_key { |row| route_rows << row }
          external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
          callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns,
            imported_functions: import_path_function_bodies)
        end

        # `.api` route paths are relative to the `@server`
        # block's `prefix:` (and go-zero mounts them under
        # it). Track the active prefix as we scan so each
        # `post /user/login` resolves to its full mounted
        # path (`/usercenter/v1/user/login`) — matching what
        # the generated `routes.go` registers via
        # `rest.WithPrefix(...)`, so the two representations
        # dedupe instead of producing half-paths.
        api_prefix = ""
        in_server_block = false
        api_types = File.extname(path) == ".api" ? api_request_types(content) : Hash(String, Array(Noir::GoStructFields::Field)).new
        named = Noir::GoNamedHandler.new(content, path, routes_by_line.values.flatten, named_scope)

        lines.each_with_index do |line, index|
          next if named.claim?(index, line)

          details = Details.new(PathInfo.new(path, index + 1))

          # Handle .api files (go-zero API definition files)
          if File.extname(path) == ".api"
            stripped = line.strip
            if stripped.starts_with?("@server")
              in_server_block = true
              api_prefix = ""
            elsif in_server_block && (pm = stripped.match(/^prefix:\s*"?([^"\s]+)"?/))
              pfx = pm[1].strip
              api_prefix = if pfx.empty?
                             ""
                           else
                             pfx.starts_with?("/") ? pfx : "/#{pfx}"
                           end
            elsif in_server_block && stripped.starts_with?(")")
              in_server_block = false
            end

            if match = line.match(API_ROUTE_LINE)
              method = match[1].upcase
              route_path = match[2]
              full_path = if api_prefix.empty?
                            route_path
                          else
                            rel = route_path.starts_with?("/") ? route_path : "/#{route_path}"
                            "#{api_prefix}#{rel}"
                          end
              new_endpoint = Endpoint.new(full_path, method, details)
              # `get /users/:id (DetailReq)`: the request type's tagged fields.
              match[3]?.try { |req| api_types[req]?.try { |fields| add_request_fields(fields, new_endpoint) } }
              result << new_endpoint
              last_endpoint = new_endpoint
            end
          end

          # Handle .go files
          if File.extname(path) == ".go"
            if ts_hits = routes_by_line[index]?
              ts_hits.each do |route|
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

            add_gozero_params(line, last_endpoint)
          end
        end

        # A named handler's body: `httpx.Parse(r, &req)` read as the tagged
        # fields of `req`'s struct, the generic body marker kept only when
        # the target does not resolve.
        named.each_bound_body do |file, body_lines, eps|
          fields = parsed_fields(body_lines, file, struct_index)
          body_lines.each { |line| eps.each { |ep| add_gozero_params(line, ep, body_marker: fields.nil?) } }
          fields.try &.each { |found, tags| eps.each { |ep| add_request_fields(found, ep, tags) } }
        end
      end

      resolve_public_dirs(public_dirs)

      result
    end

    API_ROUTE_LINE = /^\s*(get|post|put|delete|patch|head|options)\s+([^\s\(]+)(?:\s*\(\s*(\w+)\s*\))?/
    # A `.api` type body: `DetailReq {` ... `}` inside `type (...)`, or `type SearchReq {...}`.
    API_TYPE = /^\s*(?:type\s+)?([A-Za-z_]\w*)\s*\{([^{}]*)\}/m
    # `httpx.Parse(r, &req)` and its `ParseJsonBody` / `ParseForm` / `ParsePath` / `ParseHeaders` siblings.
    PARSE_CALL = /\bhttpx\.Parse(\w*)\(\s*\w+\s*,\s*&\s*([A-Za-z_]\w*)\s*\)/
    # The tag kinds each `httpx.Parse*` variant fills; `Parse` fills them all.
    PARSE_TAGS = {
      ""         => %w[path form header json],
      "Path"     => %w[path],
      "Form"     => %w[form],
      "Headers"  => %w[header],
      "JsonBody" => %w[json],
    }

    # The request types a `.api` file declares: name -> tagged fields.
    private def api_request_types(content : String) : Hash(String, Array(Noir::GoStructFields::Field))
      types = Hash(String, Array(Noir::GoStructFields::Field)).new
      content.scan(API_TYPE) do |m|
        fields = Noir::GoStructFields.literal("struct {#{m[2]}}")
        types[m[1]] = fields unless fields.empty?
      end
      types
    end

    # `{fields, tag kinds}` the `httpx.Parse*` calls in a handler body fill;
    # nil when there are none or a target does not resolve to a tagged struct.
    private def parsed_fields(lines : Array(String), file : String,
                              index : Noir::GoStructFields::Index) : Array(Tuple(Array(Noir::GoStructFields::Field), Array(String)))?
      found = nil
      lines.each do |line|
        line.scan(PARSE_CALL) do |m|
          tags = PARSE_TAGS[m[1]]? || return
          fields = index.target_fields(lines, m[2], file)
          return unless fields && fields.any? { |f| tags.any? { |key| Noir::GoStructFields.tag_value(f.tag, key) } }
          (found ||= [] of Tuple(Array(Noir::GoStructFields::Field), Array(String))) << {fields, tags}
        end
      end
      found
    end

    # go-zero's `httpx.Parse`: `path` tags from the URL, `form` tags from
    # the query string on a GET/HEAD/DELETE and the form body otherwise,
    # `header` tags from headers, `json` tags from the body (none on GET/HEAD).
    private def add_request_fields(fields : Array(Noir::GoStructFields::Field), endpoint : Endpoint,
                                   tags : Array(String) = PARSE_TAGS[""])
      bodyless = endpoint.method == "GET" || endpoint.method == "HEAD"
      fields.each do |field|
        tags.each do |tag|
          next if tag == "json" && bodyless
          name = Noir::GoStructFields.tag_value(field.tag, tag) || next
          param_type = case tag
                       when "form" then bodyless || endpoint.method == "DELETE" ? "query" : "form"
                       else             tag
                       end
          add_param_to_endpoint(Param.new(name, "", param_type), endpoint)
        end
      end
    end

    private def add_gozero_params(line : String, endpoint : Endpoint, body_marker : Bool = true)
      ["Query", "PostForm", "GetHeader", "PathParam", "FormValue"].each do |pattern|
        if line.includes?("#{pattern}(")
          add_param_to_endpoint(get_param(line, pattern), endpoint)
        end
      end
      Noir::GoRequestParamExtractor.header_params(line).each { |header| add_param_to_endpoint(header, endpoint) }

      # gozero's canonical body-binding entrypoint is
      # `httpx.Parse(r, &req)` / `httpx.ParseJsonBody`;
      # both populate the request body. `json.NewDecoder`
      # is also common in raw handlers. `httpx.Parse` binds a GET's
      # `form:` fields from the query string, so a GET gets no JSON body.
      bodyless = endpoint.method == "GET" || endpoint.method == "HEAD"
      if body_marker && (line.includes?("httpx.ParseJsonBody(") || line.matches?(/json\.NewDecoder\(.+\.Body\)/) ||
         (line.includes?("httpx.Parse(") && !bodyless))
        add_param_to_endpoint(Param.new("body", "", "json"), endpoint)
      end

      # `httpx.ParseForm` binds form fields: the query string on a GET,
      # the form body otherwise.
      if line.includes?("httpx.ParseForm(")
        form_type = bodyless ? "query" : "form"
        if match = line.match(/httpx\.ParseForm\(\s*[^,]+,\s*"([^"]+)"/)
          add_param_to_endpoint(Param.new(match[1], "", form_type), endpoint)
        elsif !bodyless
          add_param_to_endpoint(Param.new("body", "", form_type), endpoint)
        end
      end
    end

    # Type the param by the actual accessor name. The previous
    # version always returned `"query"` regardless of accessor, so
    # `r.PathParam("id")` and `r.GetHeader("X-Token")` surfaced as
    # query params — a mis-classification that broke downstream
    # consumers (auth taggers, OpenAPI export) that key off
    # `param_type`.
    def get_param(line : String, pattern : String) : Param
      param_type = case pattern
                   when "Query"     then "query"
                   when "PostForm"  then "form"
                   when "FormValue" then "form"
                   when "GetHeader" then "header"
                   when "PathParam" then "path"
                   else                  "query"
                   end

      # `get_param` is only ever called with one of the five patterns
      # `PARAM_ACCESSOR_PATTERNS` was built from (see the loop above), so
      # this lookup always hits — no interpolated-regex fallback needed.
      if match = line.match(PARAM_ACCESSOR_PATTERNS[pattern])
        return Param.new(match[1], "", param_type)
      end
      Param.new("", "", "")
    end
  end
end
