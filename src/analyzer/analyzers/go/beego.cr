require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Beego < GoEngine
    analyzer_for "go_beego"

    IMPORT_MARKER = "github.com/beego/beego"

    # One precompiled matcher instead of a `String#includes?` scan per
    # `.go` file: `includes?` runs Rabin-Karp over the whole buffer and
    # the marker is absent in the overwhelming majority of files in a
    # polyglot repo, so every one of them pays the full scan. See
    # `Analyzer#content_matches?`.
    IMPORT_MARKER_RE = Regex.union(IMPORT_MARKER)

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile), and this fixed accessor set used to be
    # rebuilt for every line — precompile it once at load time.
    CONTEXT_GETTER_PATTERNS = ["GetString", "GetStrings", "GetInt", "GetInt8", "GetUint8", "GetInt16", "GetUint16", "GetInt32", "GetUint32",
                               "GetInt64", "GetUint64", "GetBool", "GetFloat"].map do |pattern|
      {pattern, /#{pattern}\(\s*"([^"]*)"\s*[,)]/}
    end

    # Beego's `Context.Input` accessors (`c.Ctx.Input.Query("owner")`) and
    # `c.Input().Get("id")`, with the param type each reads.
    INPUT_ACCESSORS = {
      /\.Input\s*\.\s*Query\s*\(\s*"([^"]+)"/         => "query",
      /\.Input\s*\(\s*\)\s*\.\s*Get\s*\(\s*"([^"]+)"/ => "query",
      /\.Input\s*\.\s*Header\s*\(\s*"([^"]+)"/        => "header",
      /\.Input\s*\.\s*Cookie\s*\(\s*"([^"]+)"/        => "cookie",
    }

    # `&controllers.ApiController{}` on a `web.Router` line: the
    # controller's package qualifier (if any) and type.
    CONTROLLER_LITERAL = /&\s*(?:(\w+)\s*\.\s*)?([A-Z]\w*)\s*\{/
    CONTROLLER_ARG     = /Router\s*\(\s*[^,]+,\s*([a-z_]\w*)\s*[,)]/
    METHOD_RECEIVER    = /\Afunc\s*\(\s*\w*\s*\*?\s*(\w+)\s*\)/

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Pre-pass for cross-file identifier-handler resolution. Beego's
      # `web.Get("/x", h)` shape is picked up by `extract_routes`, and
      # callee resolution wires identical to Gin/Echo/etc. Beego doesn't
      # use group routes, so we just need file_contents — no fixpoint.
      file_contents = read_package_file_contents
      package_function_bodies = lazy_package_bodies(file_contents)
      # Per-directory controller-method map so mapping-less
      # `web.Router("/x", &Ctrl{})` registrations resolve to the exact
      # HTTP methods the controller implements.
      package_controller_methods = collect_package_controller_methods(file_contents)
      # Both route parses of every Beego-importing file, on the worker
      # threads; the pass below consumes them (see `prefetch_sources`).
      candidates = file_contents.keys.select do |path|
        !go_test_path?(path) && content_matches?(file_contents[path], IMPORT_MARKER_RE)
      end
      prefetched = prefetch_sources(candidates, file_contents) do |path, content|
        {Noir::TreeSitterGoRouteExtractor.extract_beego_routes(content, ts_controller_methods_for_directory(package_controller_methods, File.dirname(path))),
         Noir::TreeSitterGoRouteExtractor.extract_routes(content)}
      end
      named_scope = named_handler_scope(file_contents)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)
        content = read_file_content(path)
        next unless content_matches?(content, IMPORT_MARKER_RE)
        lines = GoEngine.strip_comments(content).lines
        raw_lines = content.lines
        last_endpoint = Endpoint.new("", "")

        # Functional `web.Get("/x", h)` verb routes plus
        # controller-style `web.Router("/x", &Ctrl{}, "get:M")`
        # registrations — the latter is Beego's dominant idiom.
        controller_methods = ts_controller_methods_for_directory(package_controller_methods, File.dirname(path))
        beego_routes, verb_routes = prefetched[path]? ||
                                    {Noir::TreeSitterGoRouteExtractor.extract_beego_routes(content, controller_methods),
                                     Noir::TreeSitterGoRouteExtractor.extract_routes(content)}
        # Track which lines are `web.Router` registrations so the
        # controller-method callee fallback below only fires for
        # them — never for a `web.Get` verb route whose handler
        # text happens to collide with a method name.
        beego_router_lines = Set(Int32).new
        beego_routes.each { |r| beego_router_lines << r.line }
        import_aliases = beego_routes.empty? ? Hash(String, String).new : Noir::GoCalleeExtractor.extract_import_aliases(content)
        ts_routes = verb_routes + beego_routes
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        # Resolve 1-hop callees for every route (see Gin).
        route_rows = Set(Int32).new
        routes_by_line.each_key { |row| route_rows << row }
        external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)
        named = Noir::GoNamedHandler.new(content, path, verb_routes, named_scope)

        lines.each_with_index do |line, index|
          next if named.claim?(index, line)

          details = Details.new(PathInfo.new(path, index + 1))

          if ts_hits = routes_by_line[index]?
            ts_hits.each do |route|
              controller_body = beego_router_lines.includes?(route.line) ? controller_method(import_aliases, path, content, raw_lines, route, named_scope) : nil
              Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                # `/api/notify-payment/?:owner/?:payment`: `?:` is an optional
                # segment, not a query string.
                new_endpoint = Endpoint.new(route.path.gsub("/?:", "/:"), verb, details)
                if entries = callees_by_route[route.line]?
                  entries.each do |entry|
                    name, callee_path, callee_line = entry
                    new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                elsif callees_needed? && controller_body &&
                      (body_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(controller_body.file_path)))
                  # `web.Router` routes carry the controller method name in
                  # `handler`; the registration call doesn't pass it as an
                  # argument, so walk the method body here.
                  Noir::GoCalleeExtractor.callees_in_body(controller_body, body_fns).each do |name, callee_path, callee_line|
                    new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end
                if controller_body
                  new_endpoint.handler = Handler.new("#{controller_body.source.match(METHOD_RECEIVER).try(&.[1])}.#{route.handler}",
                    controller_body.file_path, controller_body.start_row + 1)
                  controller_body.source.each_line { |body_line| add_beego_params(body_line, new_endpoint) }
                end
                new_endpoint.handler = named.handler_for(route) unless beego_router_lines.includes?(route.line)
                result << new_endpoint
                named.bind(route, new_endpoint) unless beego_router_lines.includes?(route.line)
                last_endpoint = new_endpoint
              end
            end
          end

          add_beego_params(line, last_endpoint)
        end

        named.each_attribution { |line, ep| add_beego_params(line, ep) }
      end

      resolve_public_dirs(public_dirs)

      result
    end

    # The controller method a `web.Router` mapping names
    # (`&controllers.ApiController{}, "GET:GetUsers"`): looked up on that
    # controller type in its own package (the qualifier's import), or in
    # this file's package for an unqualified literal (or a local bound to
    # one). Nil unless exactly one method of that type matches.
    private def controller_method(import_aliases : Hash(String, String), path : String, content : String, raw_lines : Array(String),
                                  route : Noir::TreeSitterGoRouteExtractor::Route,
                                  scope : Noir::GoNamedHandler::Scope) : Noir::GoCalleeExtractor::FunctionBody?
      return if route.handler.empty?
      text = raw_lines[route.line]? || return
      text += raw_lines[route.line + 1]? || "" unless text.matches?(CONTROLLER_LITERAL) || text.matches?(CONTROLLER_ARG)
      # `web.Router("/users", ctrl, ...)` with `ctrl := &UserController{}`
      # earlier in the file.
      literal = text.match(CONTROLLER_LITERAL) ||
                text.match(CONTROLLER_ARG).try { |arg| content.match(Regex.new("\\b#{Regex.escape(arg[1])}\\s*:?=\\s*#{CONTROLLER_LITERAL.source}")) }
      unless literal
        # Type unknown: the one method of that name in this package, if one.
        local = scope.bodies.methods_for(File.dirname(path))[route.handler]?
        return local.try { |bodies| bodies.first if bodies.size == 1 }
      end
      dir = if qualifier = literal[1]?
              import_aliases[qualifier]?.try { |import| scope.import_dirs[import]? } || return
            else
              File.dirname(path)
            end
      bodies = scope.bodies.methods_for(dir)[route.handler]? || return
      matches = bodies.select { |body| body.source.match(METHOD_RECEIVER).try(&.[1]) == literal[2] }
      matches.first if matches.size == 1
    end

    private def add_beego_params(line : String, endpoint : Endpoint)
      INPUT_ACCESSORS.each do |accessor, type|
        next unless line.includes?("Input")
        line.scan(accessor) { |m| add_param_to_endpoint(Param.new(m[1], "", type), endpoint) }
      end
      CONTEXT_GETTER_PATTERNS.each do |pattern, getter_regex|
        # Quote-bounded + scan so two accessor calls on one line
        # each yield their own param (greedy `(.*)` captured across
        # both, producing one garbage name).
        next unless line.includes?(pattern)
        line.scan(getter_regex) do |m|
          endpoint.params << Param.new(m[1], "", "query")
        end
      end

      if line.includes?("GetCookie(")
        match = line.match(/GetCookie\(\s*\"([^"]*)\"\s*\)/)
        if match
          endpoint.params << Param.new(match[1], "", "cookie")
        end
      end

      if line.includes?("GetSecureCookie(")
        match = line.match(/GetSecureCookie\(\s*\"([^"]*)\"\s*\)/)
        if match
          endpoint.params << Param.new(match[1], "", "cookie")
        end
      end
    end
  end
end
