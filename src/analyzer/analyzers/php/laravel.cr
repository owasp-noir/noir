require "../../engines/php_engine"
require "../../../minilexers/php_lexer"

module Analyzer::Php
  class Laravel < PhpEngine
    analyzer_for "php_laravel"

    @method_def_regexes = Hash(String, Regex).new

    private record RouteGroup, prefix : String, body : String, body_start : Int32, body_end : Int32

    private record ResourceRouteCall, resource : String, statement : String, start_pos : Int32

    private record ResourceEndpointTemplate, action : String, path : String, method : String

    # Everything the route scans need that is fixed for the body being
    # analyzed — one route file, or one `Route::…->group(...)` body during the
    # recursive pass. Bundled so the shared scan helpers below take the body
    # once instead of threading eight arguments through every call.
    private record RouteScanContext,
      content : String,
      file_path : String,
      include_callee : Bool,
      base_line : Int32,
      lexer : Noir::PhpLexer,
      imports : Hash(String, String),
      route_groups : Array(RouteGroup),
      skip_ranges : Array(Range(Int32, Int32)),
      handler_bodies : Array(Range(Int32, Int32))

    alias ControllerActionBody = Tuple(String, String, Int32)
    alias ControllerActionMap = Hash(String, ControllerActionBody)
    EMPTY_RESOURCE_PARAMS = {} of String => String

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Analyze Laravel route files. The framework convention is
      # `routes/web.php` and `routes/api.php`, but real apps routinely
      # split route registrations across additional files in the same
      # directory: `routes/auth.php` (Breeze/Fortify), `routes/admin.php`,
      # `routes/channels.php`, and project-specific names like koel's
      # `routes/api.base.php` / `routes/web.base.php`. Treat any `.php`
      # file living directly under a `routes/` directory as a candidate —
      # the verb scans only emit on `Route::<verb>(...)` calls, so
      # non-routing siblings such as `console.php` (Artisan commands) and
      # `channels.php` (broadcast channels) contribute nothing.
      if laravel_route_file?(path)
        endpoints.concat(analyze_routes_file(path))
      end

      # Analyze Laravel controller files
      if path.includes?("app/Http/Controllers/") && path.ends_with?(".php")
        endpoints.concat(analyze_controller_file(path))
      end

      endpoints
    end

    private def laravel_route_file?(path : String) : Bool
      return false unless path.ends_with?(".php")
      # Match any `.php` under a `routes/` directory at any depth. Larger
      # apps group routes in subdirectories — snipe-it keeps per-resource
      # files in `routes/web/hardware.php`, `routes/web/users.php`, etc.
      # Prefer substring checks over allocating a dirname split array.
      path.includes?("/routes/") || path.includes?("\\routes\\") ||
        File.basename(File.dirname(path)) == "routes"
    end

    private def analyze_routes_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      include_callee = callees_needed?
      begin
        content = read_file_content(path)
        # `use App\Http\Controllers\...;` imports map the short class
        # names used in route handlers back to their FQCNs so callee
        # resolution can locate the controller file. Only parsed when
        # callees/ai-context are requested.
        imports = include_callee ? parse_use_imports(content) : EMPTY_IMPORTS
        endpoints = analyze_routes_content(content, "", path, include_callee, imports: imports)
      rescue e
        logger.debug "Error analyzing routes file #{path}: #{e}"
        Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      end
      endpoints
    end

    EMPTY_IMPORTS = {} of String => String

    private def analyze_controller_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = read_file_content(path)

      # Look for Laravel Route attributes on controller methods
      # e.g., #[Route('/users', methods: ['GET'])]
      method_matches = content.scan(/#\[Route\s*\((.*?)\)\]\s*(?:public\s+)?function\s+(\w+)/m)
      method_matches.each do |match|
        attribute_content = match[1] # This is the content of the attribute

        path_match = attribute_content.match(/['"]([^'"]+)['"]/)
        next unless path_match

        route_path = path_match[1]
        params = extract_brace_path_params(route_path)
        details = Details.new(PathInfo.new(path))

        methods = [] of String
        methods_match = attribute_content.match(/methods:\s*\[([^\]]*)\]/i)
        if methods_match
          methods = extract_methods_from_array(methods_match[1])
        else
          # also check for single method: methods: 'POST' or methods: "POST"
          method_match = attribute_content.match(/methods:\s*['"]([^'"]+)['"]/)
          if method_match
            methods << method_match[1].upcase
          end
        end

        if methods.empty?
          methods << "GET"
        end

        methods.each do |http_method|
          endpoints << Endpoint.new(route_path, http_method, params, details.dup)
        end
      end

      endpoints
    end

    # `Route::get('/x', …)` and friends: the verb is capture 1, the path
    # capture 2.
    VERB_REGEX = /Route::(get|post|put|patch|delete|options|head|query)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
    # The same, behind a fluent prelude — `Route::middleware('auth')->prefix('v1')->get('/x', …)`.
    # Capture 1 is the whole prelude (a `->`-separated chain of calls; the
    # inner `[^;]*?` keeps each call's argument list inside one statement),
    # capture 2 the verb, capture 3 the path.
    CHAINED_VERB_REGEX = /Route::((?:\w+\s*\([^;]*?\)\s*->\s*)+)(get|post|put|patch|delete|options|head|query)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
    # `Route::match(['get', 'post'], '/x', …)` or `Route::addRoute('QUERY', '/x', …)`:
    # capture 1 is the verb specification (array literal or string literal), capture 2 the path.
    MATCH_REGEX = /Route::(?:match|addRoute)\s*\(\s*(\[[^\]]+\]|['"][^'"]+['"])\s*,\s*['"]([^'"]+)['"]\s*,/mi
    # The match/addRoute routes behind a fluent prelude. Capture 1 is the prelude,
    # capture 2 the verb specification, capture 3 the path.
    CHAINED_MATCH_REGEX = /Route::((?:\w+\s*\([^;]*?\)\s*->\s*)+)(?:match|addRoute)\s*\(\s*(\[[^\]]+\]|['"][^'"]+['"])\s*,\s*['"]([^'"]+)['"]\s*,/mi
    # `Route::any('/x', …)`: capture 1 is the path; the verbs are implied.
    ANY_REGEX = /Route::any\s*\(\s*['"]([^'"]+)['"]\s*,/mi
    # `Route::view` / `redirect` / `permanentRedirect`: capture 1 is the verb
    # alternation, matched but never read — Laravel serves all three over GET
    # only — and capture 2 is the path.
    STATIC_ROUTE_REGEX = /Route::(view|redirect|permanentRedirect)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
    # The static routes behind a fluent prelude. Capture 1 is the prelude,
    # capture 2 the (unread) static verb, capture 3 the path.
    CHAINED_STATIC_ROUTE_REGEX = /Route::((?:\w+\s*\([^;]*?\)\s*->\s*)+)(view|redirect|permanentRedirect)\s*\(\s*['"]([^'"]+)['"]\s*,/mi

    # Livewire Volt full-page components: `Volt::route('/users', 'users.index')`
    # registers a GET route. Capture 1 is the path.
    VOLT_ROUTE_REGEX = /\bVolt::route\s*\(\s*['"]([^'"]+)['"]\s*,/mi

    # Any `Route::…('path', …` registration, whatever verb or chain precedes
    # it. Used only to locate handler-closure bodies up front; the six scans
    # above are what actually decide which registrations become endpoints.
    ROUTE_REGISTRATION_RE = /Route::(?:\w+\s*\([^;]*?\)\s*->\s*)*\w+\s*\(\s*(?:(?:\[[^\]]*\]|['"][^'"]*['"])\s*,\s*)?['"][^'"]*['"]\s*,/mi

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool,
                                       base_line : Int32 = 1,
                                       imports : Hash(String, String) = EMPTY_IMPORTS,
                                       php_mode : Bool = false) : Array(Endpoint)
      endpoints = [] of Endpoint
      # One structural pass over this file/body. `PhpLexer` masks strings,
      # comments and heredoc/nowdoc bodies a single time; every
      # balanced-delimiter, statement-end and skip-range query below reuses
      # the same lexer instead of re-scanning the raw text per route. A whole
      # file starts outside `<?php`; a group body handed back by the recursive
      # pass below was already carved out of a PHP region.
      lexer = Noir::PhpLexer.new(content, php_mode: php_mode)
      route_groups = extract_route_groups(content, lexer)
      resource_controller_cache = {} of String => ControllerActionMap?
      # Character ranges that are inside PHP comments (`//`, `#`, `/* */`),
      # string literals (`'...'`, `"..."`) or heredoc/nowdoc bodies. The
      # verb scans below check each match against this set so a route-shaped
      # pattern that lives in a docstring, a `// Route::get(...)` comment, a
      # `"Try Route::get(...)"` string, or a `<<<SQL … SQL` heredoc doesn't
      # surface as a real endpoint.
      skip_ranges = lexer.skip_ranges
      ctx = RouteScanContext.new(content, file_path, include_callee, base_line, lexer, imports, route_groups, skip_ranges, collect_handler_bodies(content, base_line, lexer))

      # 1. Verb routes. Every scan below walks the body the same way, with the
      # same guards — `each_laravel_route` holds that walk once. What differs
      # is the pattern and what its numbered captures mean, so each scan names
      # its captures on entry rather than leaving bare indices at the use site.
      # The scans run in the order written and append in match order: dedup
      # downstream is first-wins, so both are observable.

      # Simple routes: Route::get, Route::post, etc.
      each_laravel_route(ctx, VERB_REGEX) do |route_match|
        verb, route_path = route_match[1], route_match[2]
        emit_handler_route(endpoints, ctx, route_match, [verb.upcase], build_full_path(prefix, route_path))
      end

      # The same verbs behind a fluent chain, which may carry a `->prefix(...)`.
      each_laravel_route(ctx, CHAINED_VERB_REGEX) do |route_match|
        chain, verb, route_path = route_match[1], route_match[2], route_match[3]
        emit_handler_route(endpoints, ctx, route_match, [verb.upcase], chained_full_path(prefix, chain, route_path))
      end

      # Route::match(['get', 'post'], ...) / Route::addRoute('QUERY', ...) — the verbs come from the array or string literal.
      each_laravel_route(ctx, MATCH_REGEX) do |route_match|
        verb_array, route_path = route_match[1], route_match[2]
        emit_handler_route(endpoints, ctx, route_match, extract_methods_from_array(verb_array), build_full_path(prefix, route_path))
      end

      # Chained Route::match / Route::addRoute
      each_laravel_route(ctx, CHAINED_MATCH_REGEX) do |route_match|
        chain, verb_array, route_path = route_match[1], route_match[2], route_match[3]
        emit_handler_route(endpoints, ctx, route_match, extract_methods_from_array(verb_array), chained_full_path(prefix, chain, route_path))
      end

      # Route::any(...) — one registration standing for every verb.
      each_laravel_route(ctx, ANY_REGEX) do |route_match|
        route_path = route_match[1]
        emit_handler_route(endpoints, ctx, route_match, ANY_ROUTE_HTTP_METHODS, build_full_path(prefix, route_path))
      end

      # Static routes: no handler to walk into, GET only.
      each_laravel_route(ctx, STATIC_ROUTE_REGEX) do |route_match|
        route_path = route_match[2]
        emit_static_route(endpoints, ctx, route_match, build_full_path(prefix, route_path))
      end

      # Static routes behind a fluent chain.
      each_laravel_route(ctx, CHAINED_STATIC_ROUTE_REGEX) do |route_match|
        chain, route_path = route_match[1], route_match[3]
        emit_static_route(endpoints, ctx, route_match, chained_full_path(prefix, chain, route_path))
      end

      each_laravel_route(ctx, VOLT_ROUTE_REGEX) do |route_match|
        emit_static_route(endpoints, ctx, route_match, build_full_path(prefix, route_match[1]))
      end

      # 2. Resource routes: `resource`/`apiResource`, their plural array forms
      # (one resource per `'name' => Controller` entry, sharing the call's
      # options) and the id-less `singleton`/`apiSingleton`.
      RESOURCE_CALL_RES.each_key do |kind|
        extract_resource_route_calls(content, kind, skip_ranges, lexer).each do |call|
          next if inside_laravel_group_body?(call.start_pos, route_groups) ||
                  inside_php_skip_range?(call.start_pos, skip_ranges)

          actions = resource_actions_for_statement(call.statement, default_resource_actions(kind, call.statement))
          parameter_overrides = resource_parameter_overrides_for_statement(call.statement)
          call_line = base_line + newline_count_before(content, call.start_pos)
          resource_entries(kind, call, lexer, call_line).each do |name, statement, line|
            templates = resource_route_templates(prefix, name, parameter_overrides, kind)
            endpoints.concat(create_resource_endpoints(templates, file_path, line, actions, statement, include_callee, imports, resource_controller_cache))
          end
        end
      end

      # 3. Group routes (recursive). Extract group bodies before scanning nested
      # routes so prefixed groups do not also emit unprefixed endpoints.
      route_groups.each do |group|
        new_prefix = group.prefix.empty? ? prefix : build_full_path(prefix, group.prefix)
        group_base_line = base_line + newline_count_before(content, group.body_start)
        endpoints.concat(analyze_routes_content(group.body, new_prefix, file_path, include_callee, group_base_line, imports, php_mode: true))
      end

      endpoints
    end

    # Walk `regex` over the body and yield every match that is a real
    # top-level route registration, skipping two kinds of match:
    #
    #   * inside a `Route::…->group(...)` body — the recursive group pass at
    #     the end of `analyze_routes_content` re-scans those bodies with the
    #     group prefix applied, so emitting here too would also emit them
    #     unprefixed;
    #   * inside a PHP comment, string literal or heredoc/nowdoc body — those
    #     are not code (see `skip_ranges`).
    #
    # The block emits the endpoints for one match and returns the position to
    # resume scanning from, which is how far a match consumes: past an inline
    # closure body for handler routes, past the match itself otherwise.
    private def each_laravel_route(ctx : RouteScanContext, regex : Regex, &) : Nil
      content = ctx.content
      pos = 0

      while route_match = content.match(regex, pos)
        pos = if inside_laravel_group_body?(route_match.begin(0), ctx.route_groups) ||
                 inside_php_skip_range?(route_match.begin(0), ctx.skip_ranges) ||
                 inside_handler_body?(route_match.begin(0), ctx.handler_bodies)
                route_match.end(0)
              else
                yield route_match
              end
      end
    end

    # Whether `offset` falls inside some route handler's closure body.
    private def inside_handler_body?(offset : Int32, bodies : Array(Range(Int32, Int32))) : Bool
      bodies.any?(&.includes?(offset))
    end

    # Byte ranges of every inline route-handler closure body in `content`.
    #
    # A `Route::…` call inside a handler body is not a route registration:
    # the closure runs when a request hits the outer route, not at boot, so
    # nothing it registers is part of the attack surface.
    #
    # The scan that *owns* the outer route already skipped its body —
    # `emit_handler_route` returns a position past it. But each of the six
    # scans starts at 0 and knew nothing about the others' skips, so whether a
    # nested call leaked out depended on which scan shape happened to find it:
    #
    #   Route::get('/a', function () { Route::get('/nested', …); });
    #     -> suppressed (both found by the same verb scan)
    #
    #   Route::any('/a', function () { Route::get('/nested', …); });
    #   Route::middleware('x')->prefix('p')->post('/a', function () { Route::get('/nested', …); });
    #     -> `/nested` emitted, at top level and WITHOUT the enclosing prefix,
    #        because the verb scan reached it before/independently of the scan
    #        that owns the outer route
    #
    # Collecting the ranges once, up front, makes the skip a property of the
    # content rather than of scan ordering — the same shape `skip_ranges`
    # already uses for strings, comments and heredocs.
    private def collect_handler_bodies(content : String, base_line : Int32, lexer : Noir::PhpLexer) : Array(Range(Int32, Int32))
      bodies = [] of Range(Int32, Int32)
      pos = 0

      while route_match = content.match(ROUTE_REGISTRATION_RE, pos)
        action_pos = route_match.end(0)
        if lexer.in_code?(route_match.begin(0))
          _body, next_pos, _line = extract_inline_closure_body(content, action_pos, base_line, lexer)
          bodies << (action_pos...next_pos) if next_pos > action_pos
          pos = action_pos
        else
          pos = route_match.end(0)
        end
      end

      bodies
    end

    # Append one endpoint per HTTP method for a route that has a handler — an
    # inline closure or a controller action. Returns the position to resume
    # scanning from: past an inline closure body, so a `Route::…` call nested
    # inside a handler is not registered as a route of its own.
    private def emit_handler_route(endpoints : Array(Endpoint),
                                   ctx : RouteScanContext,
                                   route_match : Regex::MatchData,
                                   methods : Array(String),
                                   full_path : String) : Int32
      content = ctx.content
      action_pos = route_match.end(0)
      route_line = ctx.base_line + newline_count_before(content, route_match.begin(0))
      handler_body, next_pos, body_start_line = extract_inline_closure_body(content, action_pos, ctx.base_line, ctx.lexer)
      params = extract_brace_path_params(full_path)

      methods.each do |http_method|
        details = Details.new(PathInfo.new(ctx.file_path, route_line))
        endpoint = Endpoint.new(full_path, http_method, params, details.dup)
        attach_route_callees(endpoint, handler_body, body_start_line, content, action_pos, ctx.file_path, ctx.imports) if ctx.include_callee
        endpoints << endpoint
      end

      next_pos
    end

    # Append the single GET endpoint a `Route::view` / `redirect` /
    # `permanentRedirect` registers. These take a view name or a target URL
    # rather than a handler, so there is no closure body to skip and no callee
    # to resolve. Returns the position to resume scanning from.
    private def emit_static_route(endpoints : Array(Endpoint),
                                  ctx : RouteScanContext,
                                  route_match : Regex::MatchData,
                                  full_path : String) : Int32
      route_line = ctx.base_line + newline_count_before(ctx.content, route_match.begin(0))
      params = extract_brace_path_params(full_path)
      details = Details.new(PathInfo.new(ctx.file_path, route_line))
      endpoints << Endpoint.new(full_path, "GET", params, details.dup)
      route_match.end(0)
    end

    # Path for a route registered behind a fluent chain. The chain is fed back
    # to `extract_group_prefix` as the `Route::…` text it would have seen ahead
    # of a `group(`, so `Route::prefix('v1')->get('/x')` picks its prefix up
    # exactly like a `Route::prefix('v1')->group(...)` body does.
    private def chained_full_path(prefix : String, chain : String, route_path : String) : String
      chain_prefix = extract_group_prefix("Route::#{chain}")
      build_full_path(build_full_path(prefix, chain_prefix), route_path)
    end

    # Attach callees for a route handler. Inline `function`/`fn` closures
    # are extracted directly. For the dominant Laravel shape —
    # `[Controller::class, 'method']`, `'Controller@method'`, or an
    # single-action `Controller::class` — resolve the controller file from the
    # route file's `use` imports and pull callees from the action body so
    # controller-based routes are no longer callee/ai-context blind spots.
    private def attach_route_callees(endpoint : Endpoint,
                                     body : String?,
                                     start_line : Int32?,
                                     content : String,
                                     action_pos : Int32,
                                     routes_file_path : String,
                                     imports : Hash(String, String))
      if body && start_line
        callees = Noir::PhpCalleeExtractor.callees_for_body(body, routes_file_path, start_line)
        attach_php_callees(endpoint, callees)
        return
      end

      action = extract_route_action(content, action_pos)
      return unless action

      resolved = resolve_controller_action_body(action[0], action[1], routes_file_path, imports)
      return unless resolved

      action_body, controller_path, controller_line = resolved
      callees = Noir::PhpCalleeExtractor.callees_for_body(action_body, controller_path, controller_line)
      attach_php_callees(endpoint, callees)
    end

    # Parse the controller reference that follows a route's path argument.
    # Returns {class, method} where `class` may be a short name (resolved
    # later via `use` imports) or a fully-qualified `\App\...` name.
    private def extract_route_action(content : String, pos : Int32) : Tuple(String, String)?
      scan_pos = pos
      while scan_pos < content.size && content[scan_pos].ascii_whitespace?
        scan_pos += 1
      end
      return unless scan_pos < content.size

      rest = content[scan_pos..]

      # [Controller::class, 'method']
      if m = rest.match(/\A\[\s*([A-Za-z_\\][\w\\]*)::class\s*,\s*['"]([A-Za-z_]\w*)['"]/)
        return {m[1], m[2]}
      end

      # 'Controller@method' / "App\\...\\Controller@method"
      if m = rest.match(/\A['"]([\w\\]+)@([A-Za-z_]\w*)['"]/)
        return {m[1], m[2]}
      end

      # Single-action (`__invoke`) controller: Controller::class
      if m = rest.match(/\A([A-Za-z_\\][\w\\]*)::class\s*\)/)
        return {m[1], "__invoke"}
      end

      nil
    end

    private def resolve_controller_action_body(class_ref : String,
                                               method_name : String,
                                               routes_file_path : String,
                                               imports : Hash(String, String)) : Tuple(String, String, Int32)?
      controller_path = resolve_controller_path(class_ref, routes_file_path, imports)
      return unless controller_path && File.exists?(controller_path)

      content = read_file_content(controller_path)
      # Memoized: an interpolated regex literal recompiles (PCRE2 JIT) on
      # every evaluation, and action names repeat across controllers.
      method_regex = @method_def_regexes[method_name] ||= /(?:public|protected|private)\s+(?:static\s+)?function\s+#{Regex.escape(method_name)}\s*\(/
      method_match = content.match(method_regex)
      return unless method_match

      body_info = extract_php_method_body_after(content, method_match.begin(0))
      return unless body_info

      body, start_line = body_info
      {body, controller_path, start_line}
    rescue e
      logger.debug "Error resolving Laravel handler #{class_ref}::#{method_name}: #{e}"
      nil
    end

    # Map a (possibly short or aliased) class reference to a controller file
    # path. The route file's `use` imports resolve the leading segment —
    # both `use App\...\FooController;` (short name) and
    # `use BookStack\Settings as SettingControllers;` (namespace alias) — and
    # Laravel's PSR-4 root namespace maps to `app/`. The root namespace is not
    # always `App\`: BookStack uses `BookStack\ => app/`, so the first segment
    # is dropped generically rather than matched against a literal `App`.
    private def resolve_controller_path(class_ref : String,
                                        routes_file_path : String,
                                        imports : Hash(String, String)) : String?
      segments = class_ref.lstrip('\\').split('\\').reject(&.empty?)
      return if segments.empty?

      if mapped = imports[segments[0]]?
        segments = mapped.lstrip('\\').split('\\').reject(&.empty?) + segments[1..]
      end
      return unless segments.size >= 2

      root = laravel_project_root(routes_file_path)
      return unless root

      candidates = [] of String
      candidates << File.join(root, "app", "#{segments[1..].join("/")}.php") if segments.size >= 2
      candidates << File.join(root, "app", "Http", "Controllers", "#{segments.join("/")}.php")
      candidates << File.join(root, "app", "Http", "Controllers", "#{segments.last}.php") if segments.size == 1
      candidates.find { |candidate| File.exists?(candidate) } || candidates.first?
    end

    private def laravel_project_root(routes_file_path : String) : String?
      marker = "/routes/"
      idx = routes_file_path.rindex(marker)
      return unless idx
      routes_file_path[0...idx]
    end

    private def parse_use_imports(content : String) : Hash(String, String)
      imports = {} of String => String

      # Plain imports: `use App\Http\Controllers\FooController;` (optional alias).
      content.scan(/(?:\A|[;\n{])\s*use\s+([A-Za-z_\\][\w\\]*)(?:\s+as\s+([A-Za-z_]\w*))?\s*;/) do |match|
        fqcn = match[1]
        short = match[2]? || fqcn.split('\\').last
        imports[short] = fqcn unless short.empty?
      end

      # Grouped imports: `use App\Http\Controllers\{FooController, BarController as Bar};`
      content.scan(/(?:\A|[;\n{])\s*use\s+([A-Za-z_\\][\w\\]*\\)\{([^}]+)\}/) do |match|
        prefix = match[1]
        match[2].split(',').each do |entry|
          item = entry.strip
          next if item.empty?
          next unless m = item.match(/\A([A-Za-z_\\][\w\\]*)(?:\s+as\s+([A-Za-z_]\w*))?\z/)
          fqcn = prefix + m[1]
          short = m[2]? || m[1].split('\\').last
          imports[short] = fqcn unless short.empty?
        end
      end

      imports
    end

    private def extract_inline_closure_body(content : String, pos : Int32, base_line : Int32, lexer : Noir::PhpLexer) : Tuple(String?, Int32, Int32?)
      return {nil, pos, nil} unless pos < content.size

      scan_pos = pos
      while scan_pos < content.size && content[scan_pos].ascii_whitespace?
        scan_pos += 1
      end
      return {nil, pos, nil} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      match = content[scan_pos..].match(closure_regex)
      return extract_arrow_closure_body(content, scan_pos, pos, base_line, lexer) unless match

      brace_pos = scan_pos + match[0].size - 1
      body_end = lexer.matching_delimiter(brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = base_line + newline_count_before(content, brace_pos)
      {content[(brace_pos + 1)...body_end], body_end + 1, body_start_line}
    end

    private def extract_arrow_closure_body(content : String,
                                           scan_pos : Int32,
                                           fallback_pos : Int32,
                                           base_line : Int32,
                                           lexer : Noir::PhpLexer) : Tuple(String?, Int32, Int32?)
      arrow_regex = /\A(?:static\s+)?fn\s*\([^)]*\)\s*(?::\s*[^=]+)?=>/i
      match = content[scan_pos..].match(arrow_regex)
      return {nil, fallback_pos, nil} unless match

      body_start = scan_pos + match[0].size
      body_end = lexer.expression_end(body_start)
      return {nil, fallback_pos, nil} unless body_end > body_start

      body_start_line = base_line + newline_count_before(content, body_start)
      {content[body_start...body_end], body_end, body_start_line}
    end

    # True when `pos` falls inside any skip range (PHP comment, string
    # literal or heredoc/nowdoc body — see `PhpLexer#skip_ranges`). Cheap on
    # the ~few-hundred-range count seen in real Laravel routes files.
    private def inside_php_skip_range?(pos : Int32, ranges : Array(Range(Int32, Int32))) : Bool
      ranges.any?(&.covers?(pos))
    end

    private def extract_route_groups(content : String, lexer : Noir::PhpLexer) : Array(RouteGroup)
      groups = [] of RouteGroup
      # `[^;()]*` (not `[^;]*?`) keeps each chained-call repetition unambiguous,
      # avoiding exponential backtracking (ReDoS) on long fluent chains that
      # don't terminate in `group(`.
      group_regex = /Route::(?:\w+\s*\([^;()]*\)\s*->\s*)*group\s*\(/mi
      pos = 0

      while group_match = content.match(group_regex, pos)
        group_start = group_match.begin(0)
        # Only treat a `Route::group(` as real when it is code — one inside a
        # string/comment/heredoc would otherwise register a bogus group range
        # that swallows or mis-prefixes the real routes around it.
        body_info = lexer.in_code?(group_start) ? extract_group_closure_body_after(content, group_match.end(0), lexer) : nil
        if body_info
          body, body_start, body_end = body_info
          prelude = content[group_start...body_start]
          groups << RouteGroup.new(extract_group_prefix(prelude), body, body_start, body_end)
          pos = body_end + 1
        else
          pos = group_match.end(0)
        end
      end

      groups
    end

    private def extract_group_closure_body_after(content : String, pos : Int32, lexer : Noir::PhpLexer) : Tuple(String, Int32, Int32)?
      return unless pos < content.size

      context = content[pos..]
      # Match the group closure, allowing `static`, a `use (...)` capture,
      # and a return type (`: void`) between the parameter list and the
      # body — koel and other modern Laravel apps write
      # `->group(static function (): void { ... })`, which the previous
      # `function (...) {` pattern missed, dropping the group prefix from
      # every nested route.
      function_match = context.match(/(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{;=]+)?\{/mi)
      return unless function_match

      function_start = function_match.begin(0)
      pre_function = context[0...function_start]
      return if pre_function.includes?(";")

      brace_pos = pos + function_match.end(0) - 1
      body_end = lexer.matching_delimiter(brace_pos)
      return unless body_end

      {content[(brace_pos + 1)...body_end], brace_pos + 1, body_end}
    end

    private def extract_group_prefix(prelude : String) : String
      if prefix_match = prelude.match(/(?:->|::)prefix\s*\(\s*['"]([^'"]+)['"]\s*\)/i)
        return prefix_match[1]
      end

      if prefix_match = prelude.match(/['"]prefix['"]\s*=>\s*['"]([^'"]+)['"]/i)
        return prefix_match[1]
      end

      ""
    end

    private def inside_laravel_group_body?(pos : Int32, groups : Array(RouteGroup)) : Bool
      groups.any? { |group| pos >= group.body_start && pos < group.body_end }
    end

    private def create_resource_endpoints(templates : Array(ResourceEndpointTemplate),
                                          file_path : String,
                                          line : Int32,
                                          actions : Array(String),
                                          statement : String,
                                          include_callee : Bool,
                                          imports : Hash(String, String),
                                          controller_cache : Hash(String, ControllerActionMap?)) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path, line))

      templates.each do |route_info|
        action = route_info.action
        path = route_info.path
        method = route_info.method
        next unless actions.includes?(action)

        params = extract_brace_path_params(path)
        endpoint = Endpoint.new(path, method, params, details)
        attach_resource_action_callees(endpoint, statement, action, file_path, imports, controller_cache) if include_callee
        endpoints << endpoint
      end

      endpoints
    end

    RESOURCE_ACTIONS     = ["index", "create", "store", "show", "edit", "update", "destroy"]
    API_RESOURCE_ACTIONS = ["index", "store", "show", "update", "destroy"]

    private def singleton_kind?(kind : String) : Bool
      kind.ends_with?("ingleton")
    end

    # Actions a call registers before `only`/`except`. A singleton has no
    # index; `->creatable()` adds create/store/destroy (no create form for
    # the API variant) and `->destroyable()` adds destroy.
    private def default_resource_actions(kind : String, statement : String) : Array(String)
      api = kind.starts_with?("api")
      return api ? API_RESOURCE_ACTIONS : RESOURCE_ACTIONS unless singleton_kind?(kind)

      actions = api ? ["show", "update"] : ["show", "edit", "update"]
      if statement.matches?(/->\s*creatable\s*\(/)
        actions.concat(api ? ["store", "destroy"] : ["create", "store", "destroy"])
      elsif statement.matches?(/->\s*destroyable\s*\(/)
        actions << "destroy"
      end
      actions
    end

    # A singleton acts on the resource path itself; it has no `{id}` member.
    private def resource_route_templates(prefix : String, resource : String, parameter_overrides : Hash(String, String), kind : String) : Array(ResourceEndpointTemplate)
      collection_path = resource_collection_path(prefix, resource, parameter_overrides)
      member_path = if singleton_kind?(kind)
                      collection_path
                    else
                      "#{collection_path}/{#{resource_param_name_for_segment(resource_segments(resource).last, parameter_overrides)}}"
                    end
      [
        ResourceEndpointTemplate.new("index", collection_path, "GET"),
        ResourceEndpointTemplate.new("create", "#{collection_path}/create", "GET"),
        ResourceEndpointTemplate.new("store", collection_path, "POST"),
        ResourceEndpointTemplate.new("show", member_path, "GET"),
        ResourceEndpointTemplate.new("edit", "#{member_path}/edit", "GET"),
        ResourceEndpointTemplate.new("update", member_path, "PUT"),
        ResourceEndpointTemplate.new("update", member_path, "PATCH"),
        ResourceEndpointTemplate.new("destroy", member_path, "DELETE"),
      ]
    end

    RESOURCES_ENTRY_RE = /['"]([^'"]+)['"]\s*=>\s*(\\?[A-Za-z_][\w\\]*::class|['"][^'"]*['"])/

    # `{name, statement, line}` for each resource a call registers. The
    # plural forms take a `['photos' => PhotoController::class, ...]` array;
    # each entry gets a one-resource statement so callee lookup finds its
    # controller.
    private def resource_entries(kind : String, call : ResourceRouteCall, lexer : Noir::PhpLexer, call_line : Int32) : Array(Tuple(String, String, Int32))
      return [{call.resource, call.statement, call_line}] unless kind.ends_with?("esources")

      entries = [] of Tuple(String, String, Int32)
      head = call.statement.match(RESOURCE_CALL_RES[kind])
      return entries unless head
      open = call.start_pos + head.end(0) - 1
      close = lexer.matching_delimiter(open)
      return entries unless close

      # Lines counted incrementally over the lexer's char array: per-entry
      # `newline_count_before` would rescan from the file start each time.
      line = call_line
      last = call.start_pos
      call.statement[head.end(0)...(close - call.start_pos)].scan(RESOURCES_ENTRY_RE) do |m|
        pos = open + 1 + m.begin(0)
        (last...pos).each { |i| line += 1 if lexer.masked[i] == '\n' }
        last = pos
        entries << {m[1], "Route::resource('#{m[1]}', #{m[2]})", line}
      end
      entries
    end

    private def resource_collection_path(prefix : String, resource : String, parameter_overrides : Hash(String, String)) : String
      expanded = [] of String

      resource.split('/').reject(&.empty?).each do |part|
        nested = part.split('.').reject(&.empty?)
        next if nested.empty?

        nested.each_with_index do |segment, index|
          expanded << segment
          expanded << "{#{resource_param_name_for_segment(segment, parameter_overrides)}}" if index < nested.size - 1
        end
      end

      build_full_path(prefix, expanded.join("/"))
    end

    private def attach_resource_action_callees(endpoint : Endpoint,
                                               statement : String?,
                                               action : String,
                                               routes_file_path : String,
                                               imports : Hash(String, String),
                                               controller_cache : Hash(String, ControllerActionMap?))
      return unless statement
      class_ref = extract_resource_controller(statement)
      return unless class_ref

      action_map = if controller_cache.has_key?(class_ref)
                     controller_cache[class_ref]
                   else
                     resolved_actions = resolve_controller_action_bodies(class_ref, routes_file_path, imports)
                     controller_cache[class_ref] = resolved_actions
                     resolved_actions
                   end
      return unless action_map

      resolved = action_map[action]?
      return unless resolved

      action_body, controller_path, controller_line = resolved
      callees = Noir::PhpCalleeExtractor.callees_for_body(action_body, controller_path, controller_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_resource_controller(statement : String) : String?
      if match = statement.match(/,\s*([A-Za-z_\\][\w\\]*)::class\b/)
        return match[1]
      end

      nil
    end

    private def resolve_controller_action_bodies(class_ref : String,
                                                 routes_file_path : String,
                                                 imports : Hash(String, String)) : ControllerActionMap?
      controller_path = resolve_controller_path(class_ref, routes_file_path, imports)
      return unless controller_path && File.exists?(controller_path)

      content = read_file_content(controller_path)
      actions = ControllerActionMap.new
      content.scan(/(?:public|protected|private)\s+(?:static\s+)?function\s+([A-Za-z_]\w*)\s*\(/) do |method_match|
        method_name = method_match[1]
        next unless RESOURCE_ACTIONS.includes?(method_name)
        body_info = extract_php_method_body_after(content, method_match.begin(0))
        next unless body_info

        body, start_line = body_info
        actions[method_name] = {body, controller_path, start_line}
      end

      actions
    rescue e
      logger.debug "Error resolving Laravel resource handler #{class_ref}: #{e}"
      nil
    end

    # Hoisted patterns for `extract_resource_route_calls` /
    # `extract_resource_action_filter` — both call sites pass literal
    # names ("resource"/"apiResource", "only"/"except"), and the previous
    # `Regex.new` interpolation recompiled the pattern on every call
    # (per file, and per resource statement respectively).
    RESOURCE_CALL_RES = {
      "resource"    => Regex.new("Route::resource\\s*\\(\\s*['\"]([^'\"]+)['\"]", Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE),
      "apiResource" => Regex.new("Route::apiResource\\s*\\(\\s*['\"]([^'\"]+)['\"]", Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE),
      # The plural forms end on the array's opening delimiter, which
      # `resource_entries` walks from.
      "resources"    => /Route::(resources)\s*\(\s*(?:\[|array\s*\()/i,
      "apiResources" => /Route::(apiResources)\s*\(\s*(?:\[|array\s*\()/i,
      "singleton"    => /Route::singleton\s*\(\s*['"]([^'"]+)['"]/i,
      "apiSingleton" => /Route::apiSingleton\s*\(\s*['"]([^'"]+)['"]/i,
    }
    ACTION_FILTER_RES = {
      "only"   => Regex.new("->\\s*only\\s*\\((.*?)\\)", Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE),
      "except" => Regex.new("->\\s*except\\s*\\((.*?)\\)", Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE),
    }

    private def extract_resource_route_calls(content : String,
                                             method_name : String,
                                             skip_ranges : Array(Range(Int32, Int32)),
                                             lexer : Noir::PhpLexer) : Array(ResourceRouteCall)
      calls = [] of ResourceRouteCall
      regex = RESOURCE_CALL_RES[method_name]
      pos = 0

      while route_match = content.match(regex, pos)
        if inside_php_skip_range?(route_match.begin(0), skip_ranges)
          pos = route_match.end(0)
        else
          statement_end = lexer.statement_end(route_match.begin(0))
          statement = content[route_match.begin(0)...statement_end]
          calls << ResourceRouteCall.new(route_match[1], statement, route_match.begin(0))
          pos = statement_end > route_match.end(0) ? statement_end : route_match.end(0)
        end
      end

      calls
    end

    # `defaults` filtered by a chained `->only([...])`/`->except([...])`, or by
    # the `['only' => [...]]` options argument the plural forms share.
    private def resource_actions_for_statement(statement : String, defaults : Array(String)) : Array(String)
      if only = extract_resource_action_filter(statement, "only")
        return defaults.select { |action| only.includes?(action) }
      end

      if except = extract_resource_action_filter(statement, "except")
        return defaults.reject { |action| except.includes?(action) }
      end

      defaults.select { |action| resource_action_allowed?(statement, action) }
    end

    private def extract_resource_action_filter(statement : String, filter_name : String) : Array(String)?
      match = statement.match(ACTION_FILTER_RES[filter_name])
      return unless match

      actions = [] of String
      match[1].scan(/['"]([^'"]+)['"]/).each do |action_match|
        actions << action_match[1].downcase
      end
      actions.empty? ? nil : actions
    end

    private def resource_parameter_overrides_for_statement(statement : String) : Hash(String, String)
      overrides = {} of String => String
      if match = statement.match(/->\s*parameters\s*\(\s*\[([^\]]+)\]\s*\)/mi)
        match[1].scan(/['"]([^'"]+)['"]\s*=>\s*['"]([^'"]+)['"]/).each do |param_match|
          overrides[param_match[1]] = param_match[2]
        end
      end

      overrides
    end

    private def resource_segments(resource : String) : Array(String)
      resource.split(/[\/.]/).reject(&.empty?)
    end

    private def resource_param_name_for_segment(segment : String, parameter_overrides : Hash(String, String) = EMPTY_RESOURCE_PARAMS) : String
      if override = parameter_overrides[segment]?
        return override
      end

      singularize_resource_segment(segment).gsub('-', '_')
    end

    private def singularize_resource_segment(segment : String) : String
      return segment[0...-3] + "y" if segment.ends_with?("ies") && segment.size > 3
      return segment[0...-2] if segment.ends_with?("ses") && segment.size > 3
      return segment[0...-1] if segment.ends_with?("s") && segment.size > 1
      segment
    end

    private def extract_methods_from_array(methods_str : String) : Array(String)
      methods = [] of String
      method_matches = methods_str.scan(/['"]([^'"]+)['"]/)
      method_matches.each do |match|
        methods << match[1].upcase
      end
      methods
    end
  end
end
