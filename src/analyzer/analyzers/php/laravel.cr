require "../../engines/php_engine"
require "../../../minilexers/php_lexer"
require "../../../utils/char_offsets"
require "../../../utils/http_symbols"

module Analyzer::Php
  class Laravel < PhpEngine
    analyzer_for "php_laravel"

    # A controller file parsed once and shared by every route that names it:
    # its `use` imports and each `function name(` signature in source order.
    # Re-deriving these per route was O(routes x controller size).
    private record ControllerSource,
      offsets : Noir::CharOffsets,
      imports : Hash(String, String),
      methods : Array(Regex::MatchData),
      first_methods : Hash(String, Regex::MatchData)

    METHOD_DEF_RE = /(?:public|protected|private)\s+(?:static\s+)?function\s+([A-Za-z_]\w*)\s*\(/
    SIGNATURE_RE  = /\G[^)]*/

    # Filled by the parallel file workers, hence the mutex.
    @controller_sources = {} of String => ControllerSource
    @form_request_params = {} of String => Array(Param)
    @source_cache_mutex = Mutex.new

    private record RouteGroup, prefix : String, body : String, body_start : Int32, body_end : Int32

    private record ResourceRouteCall, resource : String, statement : String, start_pos : Int32

    private record ResourceEndpointTemplate, action : String, path : String, method : String

    # Everything the route scans need that is fixed for the body being
    # analyzed — one route file, or one `Route::…->group(...)` body during the
    # recursive pass. Bundled so the shared scan helpers below take the body
    # once instead of threading eight arguments through every call.
    private record RouteScanContext,
      offsets : Noir::CharOffsets,
      file_path : String,
      include_callee : Bool,
      base_line : Int32,
      lexer : Noir::PhpLexer,
      imports : Hash(String, String),
      route_groups : Array(RouteGroup),
      skip_ranges : Array(Range(Int32, Int32)),
      handler_bodies : Array(Range(Int32, Int32))

    # {body, controller file, body start line, request params}
    alias ControllerActionBody = Tuple(String, String, Int32, Array(Param))
    alias ControllerActionMap = Hash(String, ControllerActionBody)
    EMPTY_RESOURCE_PARAMS = {} of String => String

    # Prefix each route file is loaded under, keyed by its expanded path.
    # Built once before the parallel file scan, so workers only read it.
    @route_file_prefixes = {} of String => String

    def analyze
      @route_file_prefixes = route_file_prefixes
      super
    end

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
        # names used in route handlers back to their FQCNs so the
        # controller file (params, callees) can be located.
        imports = parse_use_imports(content)
        prefix = @route_file_prefixes[Noir::PathScope.expand(path)]? || default_route_file_prefix(path)
        endpoints = analyze_routes_content(php_code(content), prefix, path, include_callee, imports: imports)
      rescue e
        logger.debug "Error analyzing routes file #{path}: #{e}"
        Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      end
      endpoints
    end

    # A route file's URL prefix comes from where the app loads it, not from
    # the file: `Route::prefix('api')->group(base_path('routes/api.php'))` in
    # a RouteServiceProvider (Laravel <= 10, including the older
    # `Route::group(['prefix' => 'api'], function () { require ... })`), or
    # `->withRouting(api: __DIR__.'/../routes/api.php', apiPrefix: 'v2')` in
    # `bootstrap/app.php` (Laravel 11+, `apiPrefix` defaulting to `api`),
    # whose `then:` closure registers further groups the same way.
    ROUTE_FILE_REF_RE   = /(['"])([^'"\n]*routes\/[^'"\n]*\.php)\1/
    WIRING_GROUP_RE     = /Route::(?:\w+\s*\([^;()]*\)\s*->\s*)*group\s*\(/i
    WITH_ROUTING_API_RE = /\bapi\s*:\s*(?:\[[^\]]*\]|[^,)]*)/
    API_PREFIX_RE       = /\bapiPrefix\s*:\s*['"]([^'"]*)['"]/

    private def route_file_prefixes : Hash(String, String)
      prefixes = {} of String => String
      php_source_files.each do |path|
        bootstrap = path.ends_with?("/bootstrap/app.php")
        next unless bootstrap || path.ends_with?("Provider.php")
        next if PhpEngine.test_path?(base_relative_path(path))
        begin
          content = read_file_content(path)
          next unless content.includes?("routes/")
          base = bootstrap ? File.dirname(File.dirname(path)) : composer_project_root(path)
          collect_route_wiring(php_code(content), path, base, prefixes) unless base.empty?
        rescue e
          logger.debug "Error reading Laravel route wiring #{path}: #{e}"
        end
      end
      prefixes
    end

    private def collect_route_wiring(content : String, source_path : String, base : String, prefixes : Hash(String, String)) : Nil
      lexer = Noir::PhpLexer.new(content)
      # {open paren, close paren, prefix} of every `Route::…->group(` call,
      # outermost first. A `Route::group([...], …)` carries its prefix in the
      # leading options array rather than the chain.
      groups = [] of Tuple(Int32, Int32, String)
      pos = 0
      while group_match = content.match(WIRING_GROUP_RE, pos)
        open = group_match.end(0) - 1
        pos = group_match.end(0)
        next unless lexer.in_code?(group_match.begin(0))
        next unless close = lexer.matching_delimiter(open)
        prelude = group_match[0]
        if options = content.match(/\G\s*(?:\[|array\s*\()/i, open + 1)
          options_end = lexer.matching_delimiter(options.end(0) - 1)
          prelude += content[options.begin(0)..options_end] if options_end
        end
        groups << {open, close, extract_group_prefix(prelude)}
      end

      api_spans = content.scan(WITH_ROUTING_API_RE).map { |m| m.begin(0)...m.end(0) }
      api_prefix = content.match(API_PREFIX_RE).try(&.[1]) || "api"

      content.scan(ROUTE_FILE_REF_RE) do |ref|
        at = ref.begin(0)
        relative_to = content[Math.max(0, at - 16)...at].matches?(/__DIR__\s*\.\s*\z/) ? File.dirname(source_path) : base
        prefix = groups.select { |(open, close, _)| open < at && at < close }
          .reduce("") { |acc, group| build_full_path(acc, group[2]) }
        prefix = build_full_path(api_prefix, prefix) if api_spans.any?(&.includes?(at))
        prefixes[Noir::PathScope.expand(File.join(relative_to, ref[2]))] ||= prefix
      end
    end

    # No wiring found for the file: fall back to the skeleton's own, which
    # serves `routes/api.php` under `/api` and every other file unprefixed.
    # Only for an app root (`artisan` / `bootstrap/app.php`): a package's
    # `routes/api.php` is loaded however its provider says. (Lumen, which has
    # no implicit API group, never gets here: `php_lumen` supersedes us.)
    private def default_route_file_prefix(path : String) : String
      return "" unless path.ends_with?("/routes/api.php")
      root = path[0...-"/routes/api.php".size]
      return "" unless File.exists?(File.join(root, "artisan")) || File.exists?(File.join(root, "bootstrap", "app.php"))
      "api"
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
      offsets = Noir::CharOffsets.new(content)
      route_groups = extract_route_groups(content, lexer)
      resource_controller_cache = {} of String => ControllerActionMap?
      # Character ranges that are inside PHP comments (`//`, `#`, `/* */`),
      # string literals (`'...'`, `"..."`) or heredoc/nowdoc bodies. The
      # verb scans below check each match against this set so a route-shaped
      # pattern that lives in a docstring, a `// Route::get(...)` comment, a
      # `"Try Route::get(...)"` string, or a `<<<SQL … SQL` heredoc doesn't
      # surface as a real endpoint.
      skip_ranges = lexer.skip_ranges
      ctx = RouteScanContext.new(offsets, file_path, include_callee, base_line, lexer, imports, route_groups, skip_ranges, collect_handler_bodies(offsets, base_line, lexer))

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
        extract_resource_route_calls(offsets, kind, skip_ranges, lexer).each do |call|
          next if inside_laravel_group_body?(call.start_pos, route_groups) ||
                  inside_php_skip_range?(call.start_pos, skip_ranges)

          actions = resource_actions_for_statement(call.statement, default_resource_actions(kind, call.statement))
          parameter_overrides = resource_parameter_overrides_for_statement(call.statement)
          call_line = base_line + offsets.line(call.start_pos) - 1
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
        group_base_line = base_line + offsets.line(group.body_start) - 1
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
      offsets = ctx.offsets
      pos = 0

      while route_match = offsets.match(regex, pos)
        start = offsets.begin(route_match)
        pos = if inside_laravel_group_body?(start, ctx.route_groups) ||
                 inside_php_skip_range?(start, ctx.skip_ranges) ||
                 inside_handler_body?(start, ctx.handler_bodies)
                offsets.end(route_match)
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
    private def collect_handler_bodies(offsets : Noir::CharOffsets, base_line : Int32, lexer : Noir::PhpLexer) : Array(Range(Int32, Int32))
      bodies = [] of Range(Int32, Int32)
      pos = 0

      while route_match = offsets.match(ROUTE_REGISTRATION_RE, pos)
        action_pos = offsets.end(route_match)
        if lexer.in_code?(offsets.begin(route_match))
          _body, next_pos, _line = extract_inline_closure_body(offsets, action_pos, base_line, lexer)
          bodies << (action_pos...next_pos) if next_pos > action_pos
        end
        pos = action_pos
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
      offsets = ctx.offsets
      action_pos = offsets.end(route_match)
      route_line = ctx.base_line + offsets.line(offsets.begin(route_match)) - 1
      handler_body, next_pos, body_start_line = extract_inline_closure_body(offsets, action_pos, ctx.base_line, ctx.lexer)
      action = handler_body ? nil : resolve_route_action(offsets, action_pos, ctx.file_path, ctx.imports)
      input_params = if handler_body
                       illuminate_request_params(handler_body)
                     else
                       action.try(&.[3]) || [] of Param
                     end

      methods.each do |http_method|
        details = Details.new(PathInfo.new(ctx.file_path, route_line))
        params = extract_brace_path_params(full_path) + params_for_method(input_params, http_method)
        endpoint = Endpoint.new(full_path, http_method, dedup_params(params), details.dup)
        attach_route_callees(endpoint, handler_body, body_start_line, action, ctx.file_path) if ctx.include_callee
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
      route_line = ctx.base_line + ctx.offsets.line(ctx.offsets.begin(route_match)) - 1
      params = extract_brace_path_params(full_path)
      details = Details.new(PathInfo.new(ctx.file_path, route_line))
      endpoints << Endpoint.new(full_path, "GET", params, details.dup)
      ctx.offsets.end(route_match)
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
                                     action : ControllerActionBody?,
                                     routes_file_path : String)
      if body && start_line
        callees = Noir::PhpCalleeExtractor.callees_for_body(body, routes_file_path, start_line)
        attach_php_callees(endpoint, callees)
        return
      end
      return unless action

      callees = Noir::PhpCalleeExtractor.callees_for_body(action[0], action[1], action[2])
      attach_php_callees(endpoint, callees)
    end

    # The controller action a route's handler argument names, resolved to
    # its body, file, line and request params.
    private def resolve_route_action(offsets : Noir::CharOffsets,
                                     action_pos : Int32,
                                     routes_file_path : String,
                                     imports : Hash(String, String)) : ControllerActionBody?
      action = extract_route_action(offsets, action_pos)
      return unless action
      resolve_controller_action_body(action[0], action[1], routes_file_path, imports)
    end

    # A GET (or HEAD) request carries its input in the query string.
    private def params_for_method(params : Array(Param), http_method : String) : Array(Param)
      return params unless http_method.in?("GET", "HEAD")
      params.map { |param| param.param_type == "form" ? Param.new(param.name, param.value, "query") : param }
    end

    FORM_REQUEST_HINT_RE = /([A-Za-z_\\][\w\\]*Request)\s+\$/
    RULES_METHOD_RE      = /(?:public|protected|private)\s+function\s+rules\s*\(/

    # Request params of the controller action whose `(` ends at `sig_pos` in
    # `content`: reads in its body plus the `rules()` keys of every
    # FormRequest it type-hints (`store(StorePostRequest $request)`).
    private def controller_action_params(source : ControllerSource,
                                         signature_match : Regex::MatchData,
                                         body : String,
                                         routes_file_path : String) : Array(Param)
      params = illuminate_request_params(body)
      signature = SIGNATURE_RE.match_at_byte_index(source.offsets.content, signature_match.byte_end(0)).try(&.[0]) || ""
      return params unless signature.includes?("Request")

      signature.scan(FORM_REQUEST_HINT_RE) do |m|
        next if m[1].split('\\').last == "Request"
        request_path = resolve_controller_path(m[1], routes_file_path, source.imports)
        next unless request_path && File.exists?(request_path)
        params.concat(form_request_rule_params(request_path))
      end
      dedup_params(params)
    end

    # `rules()` keys of one FormRequest file, read once per scan.
    private def form_request_rule_params(path : String) : Array(Param)
      if cached = @source_cache_mutex.synchronize { @form_request_params[path]? }
        return cached
      end

      content = read_file_content(path)
      params = [] of Param
      if (rules = content.match(RULES_METHOD_RE)) && (rules_body = extract_php_method_body_after(content, rules.begin(0)))
        params = rule_key_params(rules_body[0])
      end
      @source_cache_mutex.synchronize { @form_request_params[path] ||= params }
    end

    private def controller_source(path : String) : ControllerSource
      if cached = @source_cache_mutex.synchronize { @controller_sources[path]? }
        return cached
      end

      content = read_file_content(path)
      methods = [] of Regex::MatchData
      first_methods = {} of String => Regex::MatchData
      content.scan(METHOD_DEF_RE) do |m|
        methods << m
        first_methods[m[1]] ||= m
      end
      source = ControllerSource.new(Noir::CharOffsets.new(content), parse_use_imports(content), methods, first_methods)
      @source_cache_mutex.synchronize { @controller_sources[path] ||= source }
    end

    # The action whose signature is `signature_match`, as
    # `extract_php_method_body_after` would cut it, but in O(body): no copy of
    # the rest of the file and no newline count from the top.
    private def controller_action(source : ControllerSource,
                                  signature_match : Regex::MatchData,
                                  controller_path : String,
                                  routes_file_path : String) : ControllerActionBody?
      content = source.offsets.content
      brace = content.byte_index('{'.ord.to_u8, signature_match.byte_end(0))
      return unless brace
      close = find_matching_php_close_brace_at_byte(content, brace)
      return unless close && close > brace + 1

      body = content.byte_slice(brace + 1, close - brace - 1)
      start_line = source.offsets.line(source.offsets.char(brace))
      {body, controller_path, start_line, controller_action_params(source, signature_match, body, routes_file_path)}
    end

    # Parse the controller reference that follows a route's path argument.
    # Returns {class, method} where `class` may be a short name (resolved
    # later via `use` imports) or a fully-qualified `\App\...` name.
    private def extract_route_action(offsets : Noir::CharOffsets, pos : Int32) : Tuple(String, String)?
      scan_pos = pos
      while offsets.ascii_whitespace?(scan_pos)
        scan_pos += 1
      end
      return unless scan_pos < offsets.content.size

      # [Controller::class, 'method']
      if m = offsets.match(/\G\[\s*([A-Za-z_\\][\w\\]*)::class\s*,\s*['"]([A-Za-z_]\w*)['"]/, scan_pos)
        return {m[1], m[2]}
      end

      # 'Controller@method' / "App\\...\\Controller@method"
      if m = offsets.match(/\G['"]([\w\\]+)@([A-Za-z_]\w*)['"]/, scan_pos)
        return {m[1], m[2]}
      end

      # Single-action (`__invoke`) controller: Controller::class
      if m = offsets.match(/\G([A-Za-z_\\][\w\\]*)::class\s*\)/, scan_pos)
        return {m[1], "__invoke"}
      end

      nil
    end

    private def resolve_controller_action_body(class_ref : String,
                                               method_name : String,
                                               routes_file_path : String,
                                               imports : Hash(String, String)) : ControllerActionBody?
      controller_path = resolve_controller_path(class_ref, routes_file_path, imports)
      return unless controller_path && File.exists?(controller_path)

      source = controller_source(controller_path)
      return unless method_match = source.first_methods[method_name]?
      controller_action(source, method_match, controller_path, routes_file_path)
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

    private def extract_inline_closure_body(offsets : Noir::CharOffsets, pos : Int32, base_line : Int32, lexer : Noir::PhpLexer) : Tuple(String?, Int32, Int32?)
      size = offsets.content.size
      return {nil, pos, nil} unless pos < size

      scan_pos = pos
      while offsets.ascii_whitespace?(scan_pos)
        scan_pos += 1
      end
      return {nil, pos, nil} unless scan_pos < size

      closure_regex = /\G(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      match = offsets.match(closure_regex, scan_pos)
      return extract_arrow_closure_body(offsets, scan_pos, pos, base_line, lexer) unless match

      brace_pos = offsets.end(match) - 1
      body_end = lexer.matching_delimiter(brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = base_line + offsets.line(brace_pos) - 1
      {offsets.slice(brace_pos + 1, body_end), body_end + 1, body_start_line}
    end

    private def extract_arrow_closure_body(offsets : Noir::CharOffsets,
                                           scan_pos : Int32,
                                           fallback_pos : Int32,
                                           base_line : Int32,
                                           lexer : Noir::PhpLexer) : Tuple(String?, Int32, Int32?)
      arrow_regex = /\G(?:static\s+)?fn\s*\([^)]*\)\s*(?::\s*[^=]+)?=>/i
      match = offsets.match(arrow_regex, scan_pos)
      return {nil, fallback_pos, nil} unless match

      body_start = offsets.end(match)
      body_end = lexer.expression_end(body_start)
      return {nil, fallback_pos, nil} unless body_end > body_start

      body_start_line = base_line + offsets.line(body_start) - 1
      {offsets.slice(body_start, body_end), body_end, body_start_line}
    end

    # True when `pos` falls inside any skip range (PHP comment, string
    # literal or heredoc/nowdoc body — see `PhpLexer#skip_ranges`). Cheap on
    # the ~few-hundred-range count seen in real Laravel routes files.
    private def inside_php_skip_range?(pos : Int32, ranges : Array(Range(Int32, Int32))) : Bool
      # The lexer records its ranges in one left-to-right pass, so they are
      # sorted and disjoint: the only candidate is the first ending at/after `pos`.
      range = ranges.bsearch { |r| r.end >= pos }
      !range.nil? && range.covers?(pos)
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

        resolved = resource_action_body(statement, action, file_path, imports, controller_cache)
        params = extract_brace_path_params(path)
        params.concat(params_for_method(resolved[3], method)) if resolved
        endpoint = Endpoint.new(path, method, dedup_params(params), details)
        if include_callee && resolved
          attach_php_callees(endpoint, Noir::PhpCalleeExtractor.callees_for_body(resolved[0], resolved[1], resolved[2]))
        end
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

    # The resolved body of resource `action` on the statement's controller.
    private def resource_action_body(statement : String?,
                                     action : String,
                                     routes_file_path : String,
                                     imports : Hash(String, String),
                                     controller_cache : Hash(String, ControllerActionMap?)) : ControllerActionBody?
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
      action_map.try(&.[action]?)
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

      source = controller_source(controller_path)
      actions = ControllerActionMap.new
      source.methods.each do |method_match|
        method_name = method_match[1]
        next unless RESOURCE_ACTIONS.includes?(method_name)
        next unless action = controller_action(source, method_match, controller_path, routes_file_path)
        actions[method_name] = action
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

    private def extract_resource_route_calls(offsets : Noir::CharOffsets,
                                             method_name : String,
                                             skip_ranges : Array(Range(Int32, Int32)),
                                             lexer : Noir::PhpLexer) : Array(ResourceRouteCall)
      calls = [] of ResourceRouteCall
      regex = RESOURCE_CALL_RES[method_name]
      pos = 0

      while route_match = offsets.match(regex, pos)
        start = offsets.begin(route_match)
        match_end = offsets.end(route_match)
        if inside_php_skip_range?(start, skip_ranges)
          pos = match_end
        else
          statement_end = lexer.statement_end(start)
          statement = offsets.slice(start, statement_end)
          calls << ResourceRouteCall.new(route_match[1], statement, start)
          pos = statement_end > match_end ? statement_end : match_end
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
