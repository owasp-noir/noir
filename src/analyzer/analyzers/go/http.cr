require "../../engines/go_engine"
require "../../../miniparsers/go_request_param_extractor"

module Analyzer::Go
  class Http < GoEngine
    analyzer_for "go_http"

    IMPORT_MARKER = "net/http"

    # Registration calls that make a file worth the route parse.
    ROUTE_METHODS = ["HandleFunc", "Handle"]

    ROUTER_CALL_METHODS = /\.(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|Any|Handle|HandleFunc|Group|Use|Get|Post|Put|Patch|Delete|Route|Mount)\s*\(/

    # Whether the handler argument is a bare identifier this file registers
    # routes on (`r := gin.Default(); r.GET(...); http.Handle("/", r)`).
    private def router_mount?(route, content : String) : Bool
      name = innermost_arg(route.handler_args.last?.try(&.strip) || return false)
      return false unless name.matches?(/\A[A-Za-z_]\w*\z/)
      content.matches?(/\b#{Regex.escape(name)}#{ROUTER_CALL_METHODS.source}/) ||
        # `apiMux := http.NewServeMux()` filled by a helper of another file.
        content.matches?(/\b#{Regex.escape(name)}\s*:?=\s*&?\s*http\s*\.\s*(?:NewServeMux\s*\(|ServeMux\s*\{)/)
    end

    # `func (s *S) RegisterRoutes(mux *http.ServeMux, ...)`: the head and
    # its parameter list.
    FUNC_WITH_PARAMS = /^func\s+(?:\([^)]*\)\s*)?(\w+)\s*\(([^)]*)\)/m

    # The prefixes a `*http.ServeMux` parameter's routes are served under,
    # read off each call of the function: `registerAPI(api)` with `root.
    # Handle("/api/", http.StripPrefix("/api", api))` in the caller is
    # `/api`; a mux the caller never mounts (or passes on) is the root, ``;
    # one mounted where the prefix does not resolve (a variable pattern, a
    # wrapper) is `nil`. With no call in the scan, the routes stand as
    # written.
    # ponytail: one call level; a mux handed through two helpers before it
    # is mounted reads as the root.
    @mux_param_prefixes = Hash(String, Array(String?)).new

    private def mux_param_prefixes(function : String, index : Int32, file_contents : Hash(String, String)) : Array(String?)
      @mux_param_prefixes.put_if_absent("#{function}/#{index}") do
        prefixes = [] of String?
        call = /(?<![\w])#{Regex.escape(function)}\s*\(/
        file_contents.each_value do |content|
          next unless content.includes?(function)
          lines = content.lines
          lines.each_with_index do |line, row|
            next if line.lstrip.starts_with?("func ") || line.lstrip.starts_with?("//")
            next unless m = line.match(call)
            arg = call_argument(lines[row, 6].join('\n')[m.end..], index) || next
            prefixes << (arg.matches?(/\A\w+\z/) ? caller_mount_prefix(lines, row, arg) : "")
          end
        end
        prefixes.empty? ? [""] of String? : prefixes.uniq
      end
    end

    # The `index`th argument of a call whose arguments start `text` (just
    # after its opening parenthesis).
    private def call_argument(text : String, index : Int32) : String?
      depth = 1
      close = nil
      text.each_char_with_index do |char, i|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        if depth == 0
          close = i
          break
        end
      end
      return unless close
      Noir::TopLevelSplit.split(text[0, close], ',', Noir::TopLevelSplit::Rules.new)[index]?.try(&.strip)
    end

    # How the function around `row` mounts the mux `name`.
    private def caller_mount_prefix(lines : Array(String), row : Int32, name : String) : String?
      start = row
      while start > 0 && !lines[start].starts_with?("func ")
        start -= 1
      end
      finish = row
      while finish < lines.size - 1 && !lines[finish].starts_with?(%(}))
        finish += 1
      end
      body = lines[start..finish].join('\n')
      escaped = Regex.escape(name)
      if m = body.match(/\.\s*Handle\s*\(\s*"[^"]*"\s*,\s*http\s*\.\s*StripPrefix\s*\(\s*"([^"]*)"\s*,\s*#{escaped}\s*\)\s*\)/)
        m[1].rstrip('/')
      elsif body.matches?(/\.\s*Handle\s*\(\s*"[^"]*"\s*,\s*#{escaped}\s*\)/)
        ""
      elsif body.matches?(/\.\s*Handle(?:Func)?\s*\([^\n]*[(,]\s*#{escaped}\s*\)/)
        nil
      else
        ""
      end
    end

    # `{function, index}` of the `*http.ServeMux` parameter `name` of the
    # function around `row`, if `name` is one.
    private def mux_parameter(lines : Array(String), row : Int32, name : String) : {String, Int32}?
      start = row
      while start > 0 && !lines[start].starts_with?("func ")
        start -= 1
      end
      head = lines[start..Math.min(start + 3, lines.size - 1)].join(' ').match(FUNC_WITH_PARAMS) || return
      names = [] of String
      typed = [] of String?
      head[2].split(',').each do |piece|
        parts = piece.strip.split(/\s+/, 2)
        names << parts[0]
        typed << parts[1]?
      end
      # `a, b *http.ServeMux`: a name without a type takes the next one's.
      (names.size - 2).downto(0) { |i| typed[i] ||= typed[i + 1] }
      index = names.index(name) || return
      return unless typed[index].try(&.matches?(/\A\*?(?:\w+\.)?ServeMux\z/))
      {head[1], index}
    end

    # What a wrapper chain ends at: `api` in `requireAuth(api)` or
    # `http.StripPrefix("/v1", api)`.
    private def innermost_arg(text : String) : String
      4.times do
        break unless text.ends_with?(')') && (open = text.index('(')) && text[0, open].matches?(/\A[\w.\s]+\z/)
        text = Noir::TopLevelSplit.split(text[open + 1...-1], ',', Noir::TopLevelSplit::Rules.new).last?.try(&.strip) || break
      end
      text
    end

    def analyze
      # Source Analysis
      # Groups are irrelevant for net/http — this analyzer only ever wanted
      # the `{path => source}` cache. It used to get it from
      # `collect_package_groups_ts`, whose group fixpoint it then threw
      # away: that cost one `extract_engine_names_and_groups` tree-sitter
      # parse per `net/http`-importing file plus at least two
      # `extract_groups` parses per file in every multi-file package.
      # `read_package_file_contents` builds the identical hash (same
      # extension index, same `_test.go` filter, same reads) with no
      # parses at all.
      file_contents = read_package_file_contents
      package_function_bodies = lazy_package_bodies(file_contents)
      package_method_bodies = lazy_package_bodies(file_contents)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      named_scope = named_handler_scope(file_contents)
      resolver = Noir::GoRequestParamExtractor::Resolver.new(named_scope.bodies, file_contents, named_scope.import_dirs)
      # `route_dirs` exists only to bound the two request-param pre-passes
      # below, and those maps are consulted exclusively from
      # `params_for_routes`, which returns immediately when the file
      # produced no route. A directory whose candidate files cannot yield
      # a net/http route (`net_http_route_source?` is the extractor's own
      # necessary condition) is therefore never looked up — including it
      # only bought a tree-sitter parse of every `.go` file in it.
      route_dirs = Set(String).new
      file_contents.each do |path, content|
        dir = File.dirname(path)
        next unless Noir::TreeSitterGoRouteExtractor.net_http_route_source?(content)
        if framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ROUTE_METHODS)
          route_dirs << dir
        end
      end
      # Built per directory on first lookup, which only happens for a file
      # that produced routes — most of `route_dirs` never gets there.
      request_bodies = Noir::GoRequestParamExtractor.lazy_package_bodies_for_dirs(file_contents, route_dirs)
      # Route parses of every candidate file, on the worker threads; the pass
      # below consumes them (see `prefetch_route_sources`).
      prefetched = prefetch_route_sources(file_contents, framework_dirs, IMPORT_MARKER, ROUTE_METHODS) do |path, content|
        dir = File.dirname(path)
        Noir::TreeSitterGoRouteExtractor.extract_net_http_routes(
          content,
          external_string_values: resolver.constants(dir),
          external_functions: ts_function_bodies_for_directory(package_function_bodies, dir),
          external_methods: ts_controller_method_bodies_for_directory(package_method_bodies, dir)
        )
      end
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        dir = File.dirname(path)
        next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ROUTE_METHODS)

        external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
        external_methods = ts_controller_method_bodies_for_directory(package_method_bodies, dir)
        ts_routes = prefetched[path]? || Noir::TreeSitterGoRouteExtractor.extract_net_http_routes(
          content,
          external_string_values: resolver.constants(dir),
          external_functions: external_fns,
          external_methods: external_methods
        )
        # With no route in the file the line loop below is a
        # no-op by construction: it only ever appends to
        # `last_endpoint`, and `add_param_to_endpoint` (plus
        # the body-param branch) require a non-empty URL,
        # which the seed endpoint never has. Bail before
        # splitting the file into lines.
        next if ts_routes.empty?

        lines = GoEngine.strip_comments(content).lines
        last_endpoint = Endpoint.new("", "")

        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        # Resolve 1-hop callees for every route (see Gin/Mux).
        route_rows = Set(Int32).new
        route_methods_by_row = Hash(Int32, String).new
        routes_by_line.each do |row, routes|
          route_rows << row
          route_methods_by_row[row] = routes.first.verb
        end
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns, external_methods)
        request_fns = Noir::GoRequestParamExtractor.function_bodies_for_directory(request_bodies, dir)
        request_methods = Noir::GoRequestParamExtractor.method_bodies_for_directory(request_bodies, dir)
        params_by_route = Noir::GoRequestParamExtractor.params_for_routes(content, route_rows, route_methods_by_row, request_fns, request_methods,
          resolver: resolver, path: path)
        # A same-file named handler's accessors already arrive through
        # `params_by_route`; keep its body out of the last-route heuristic.
        named = Noir::GoNamedHandler.new(content, path, ts_routes, named_scope)

        lines.each_with_index do |line, index|
          next if named.claim?(index, line)

          details = Details.new(PathInfo.new(path, index + 1))

          if ts_hits = routes_by_line[index]?
            ts_hits.each do |route|
              # `http.Handle("/", r)` hands the tree to a router whose own
              # routes are already reported; it is a mount, not a route
              # answering every method at "/".
              next if router_mount?(route, content) || named.mount?(route)
              verbs = if route.verb.upcase == "ANY" || route.verb.upcase == "ALL"
                        Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb)
                      else
                        [route.verb]
                      end
              # A ServeMux pattern ending in `/` serves every path under it;
              # `/x/{$}` (written `/x/`) serves only `/x/`.
              subtree = route.path.ends_with?('/') && !route.raw_path.ends_with?("{$}")
              # A route on a `*http.ServeMux` parameter takes the prefix its
              # callers mount that mux under; an unresolved mount drops it.
              prefixes = mux_parameter(lines, route.line, route.router_name).try { |(fn, idx)| mux_param_prefixes(fn, idx, file_contents) } || [""] of String?
              next if prefixes.includes?(nil)
              prefixes.compact.flat_map { |prefix| verbs.map { |verb| {prefix, verb} } }.each do |(prefix, verb)|
                route_path = prefix.empty? ? route.path : "#{prefix}#{route.path}"
                new_endpoint = Endpoint.new(route_path, verb, details)
                new_endpoint.add_tag(Tag.new("go-http-path-type", "subtree", "go_http_analyzer")) if subtree
                if entries = callees_by_route[route.line]?
                  entries.each do |entry|
                    name, callee_path, callee_line = entry
                    new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end
                if params = params_by_route[route.line]?
                  params.each { |param| add_route_param(param, new_endpoint) }
                end
                new_endpoint.handler = named.handler_for(route)
                new_endpoint.resolution = route.resolution
                # The resolved definition, wherever it is declared (a method
                # value of another package, a factory's returned method).
                named.handler_body(route).try do |body|
                  Noir::GoRequestParamExtractor.params_for_body(body, verb, resolver).each { |param| add_route_param(param, new_endpoint) }
                end
                result << new_endpoint
                last_endpoint = new_endpoint
              end
            end
          end

          # Handle parameter extraction patterns in Go (identical to mux / stdlib Request usage).
          # Order: more specific first.
          if line.includes?("Query().Get(")
            add_param_to_endpoint(get_param(line, "Query"), last_endpoint)
          elsif line.includes?("PostFormValue(")
            add_param_to_endpoint(get_param(line, "PostFormValue", last_endpoint), last_endpoint)
          elsif line.includes?("FormValue(")
            add_param_to_endpoint(get_param(line, "FormValue", last_endpoint), last_endpoint)
          elsif line.includes?("Cookie(")
            add_param_to_endpoint(get_param(line, "Cookie"), last_endpoint)
          end
          Noir::GoRequestParamExtractor.header_params(line).each { |header| add_param_to_endpoint(header, last_endpoint) }

          # Stdlib-style body reads (json or raw) — same heuristic used by mux analyzer.
          if !last_endpoint.url.empty? &&
             (line.matches?(/json\.NewDecoder\([^)]*\.Body\)\s*\.\s*Decode/) ||
             line.matches?(/(?:io|ioutil)\.ReadAll\([^)]*\.Body\)/))
            body_param = Param.new("body", "", "json")
            last_endpoint.params << body_param unless last_endpoint.params.includes?(body_param)
          end
        end
      end

      result
    end

    def get_param(line : String, pattern : String, endpoint : Endpoint? = nil) : Param
      param_name = ""
      param_type = ""

      case pattern
      when "Query"
        if match = line.match(/Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "query"
        end
      when "PostFormValue"
        if match = line.match(/PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "form"
        end
      when "FormValue"
        if match = line.match(/FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = form_value_param_type(endpoint)
        end
      when "Cookie"
        if match = line.match(/Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "cookie"
        end
      end

      Param.new(param_name, "", param_type)
    end

    private def form_value_param_type(endpoint : Endpoint?) : String
      return "query" unless endpoint

      case endpoint.method
      when "GET", "HEAD", "QUERY", ""
        "query"
      else
        "form"
      end
    end

    # A `PathValue("x")` read (the handler's or a helper's it calls) is a
    # client-sent path param only when the pattern has an `{x}` / `{x...}`
    # wildcard; otherwise only server code sets it (`r.SetPathValue`).
    private def add_route_param(param : Param, endpoint : Endpoint)
      return if param.param_type == "path" &&
                !endpoint.url.includes?("{#{param.name}}") && !endpoint.url.includes?("{#{param.name}...}")
      add_param_to_endpoint(param, endpoint)
    end
  end
end
