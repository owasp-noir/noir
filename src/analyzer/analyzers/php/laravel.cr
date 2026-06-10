require "../../engines/php_engine"
require "../../../minilexers/php_lexer"

module Analyzer::Php
  class Laravel < PhpEngine
    @method_def_regexes = Hash(String, Regex).new

    private struct RouteGroup
      getter prefix, body, body_start, body_end

      def initialize(@prefix : String, @body : String, @body_start : Int32, @body_end : Int32)
      end
    end

    private struct ResourceRouteCall
      getter resource, statement, start_pos

      def initialize(@resource : String, @statement : String, @start_pos : Int32)
      end
    end

    private struct ResourceEndpointTemplate
      getter action, path, method

      def initialize(@action : String, @path : String, @method : String)
      end
    end

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
      File.dirname(path).split('/').includes?("routes")
    end

    private def analyze_routes_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      begin
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          # `use App\Http\Controllers\...;` imports map the short class
          # names used in route handlers back to their FQCNs so callee
          # resolution can locate the controller file. Only parsed when
          # callees/ai-context are requested.
          imports = include_callee ? parse_use_imports(content) : EMPTY_IMPORTS
          endpoints = analyze_routes_content(content, "", path, include_callee, imports: imports)
        end
      rescue e
        logger.debug "Error analyzing routes file #{path}: #{e}"
      end
      endpoints
    end

    EMPTY_IMPORTS = {} of String => String

    private def analyze_controller_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Look for Laravel Route attributes on controller methods
        # e.g., #[Route('/users', methods: ['GET'])]
        method_matches = content.scan(/#\[Route\s*\(([^]]*)\]\s*public\s+function\s+(\w+)/m)
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
      end

      endpoints
    end

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool,
                                       base_line : Int32 = 1,
                                       imports : Hash(String, String) = EMPTY_IMPORTS) : Array(Endpoint)
      endpoints = [] of Endpoint
      # One structural pass over this file/body. `PhpLexer` masks strings,
      # comments and heredoc/nowdoc bodies a single time; every
      # balanced-delimiter, statement-end and skip-range query below reuses
      # the same lexer instead of re-scanning the raw text per route.
      lexer = Noir::PhpLexer.new(content)
      route_groups = extract_route_groups(content, lexer)
      resource_controller_cache = {} of String => ControllerActionMap?
      # Character ranges that are inside PHP comments (`//`, `#`, `/* */`),
      # string literals (`'...'`, `"..."`) or heredoc/nowdoc bodies. The
      # per-loop verb scans below check each match against this set so a
      # route-shaped pattern that lives in a docstring, a `// Route::get(...)`
      # comment, a `"Try Route::get(...)"` string, or a `<<<SQL … SQL`
      # heredoc doesn't surface as a real endpoint.
      skip_ranges = lexer.skip_ranges

      # 1. Simple routes: Route::get, Route::post, etc.
      verb_regex = /Route::(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(verb_regex, pos)
        if inside_laravel_group_body?(route_match.begin(0), route_groups) ||
           inside_php_skip_range?(route_match.begin(0), skip_ranges)
          pos = route_match.end(0)
        else
          methods = [route_match[1].upcase]
          route_path = route_match[2]
          full_path = build_full_path(prefix, route_path)
          route_line = base_line + newline_count_before(content, route_match.begin(0))
          handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line, lexer)
          params = extract_brace_path_params(full_path)

          methods.each do |http_method|
            details = Details.new(PathInfo.new(file_path, route_line))
            endpoint = Endpoint.new(full_path, http_method, params, details.dup)
            attach_route_callees(endpoint, handler_body, body_start_line, content, route_match.end(0), file_path, imports) if include_callee
            endpoints << endpoint
          end
          pos = next_pos
        end
      end

      chained_verb_regex = /Route::((?:\w+\s*\([^;]*?\)\s*->\s*)+)(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(chained_verb_regex, pos)
        if inside_laravel_group_body?(route_match.begin(0), route_groups) ||
           inside_php_skip_range?(route_match.begin(0), skip_ranges)
          pos = route_match.end(0)
        else
          route_prefix = extract_group_prefix("Route::#{route_match[1]}")
          methods = [route_match[2].upcase]
          route_path = route_match[3]
          full_path = build_full_path(build_full_path(prefix, route_prefix), route_path)
          route_line = base_line + newline_count_before(content, route_match.begin(0))
          handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line, lexer)
          params = extract_brace_path_params(full_path)

          methods.each do |http_method|
            details = Details.new(PathInfo.new(file_path, route_line))
            endpoint = Endpoint.new(full_path, http_method, params, details.dup)
            attach_route_callees(endpoint, handler_body, body_start_line, content, route_match.end(0), file_path, imports) if include_callee
            endpoints << endpoint
          end
          pos = next_pos
        end
      end

      match_regex = /Route::match\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(match_regex, pos)
        if inside_laravel_group_body?(route_match.begin(0), route_groups) ||
           inside_php_skip_range?(route_match.begin(0), skip_ranges)
          pos = route_match.end(0)
        else
          methods = extract_methods_from_array(route_match[1])
          route_path = route_match[2]
          full_path = build_full_path(prefix, route_path)
          route_line = base_line + newline_count_before(content, route_match.begin(0))
          handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line, lexer)
          params = extract_brace_path_params(full_path)

          methods.each do |http_method|
            details = Details.new(PathInfo.new(file_path, route_line))
            endpoint = Endpoint.new(full_path, http_method, params, details.dup)
            attach_route_callees(endpoint, handler_body, body_start_line, content, route_match.end(0), file_path, imports) if include_callee
            endpoints << endpoint
          end
          pos = next_pos
        end
      end

      any_regex = /Route::any\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(any_regex, pos)
        if inside_laravel_group_body?(route_match.begin(0), route_groups) ||
           inside_php_skip_range?(route_match.begin(0), skip_ranges)
          pos = route_match.end(0)
        else
          methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
          route_path = route_match[1]
          full_path = build_full_path(prefix, route_path)
          route_line = base_line + newline_count_before(content, route_match.begin(0))
          handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line, lexer)
          params = extract_brace_path_params(full_path)

          methods.each do |http_method|
            details = Details.new(PathInfo.new(file_path, route_line))
            endpoint = Endpoint.new(full_path, http_method, params, details.dup)
            attach_route_callees(endpoint, handler_body, body_start_line, content, route_match.end(0), file_path, imports) if include_callee
            endpoints << endpoint
          end
          pos = next_pos
        end
      end

      static_route_regex = /Route::(view|redirect|permanentRedirect)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(static_route_regex, pos)
        if inside_laravel_group_body?(route_match.begin(0), route_groups) ||
           inside_php_skip_range?(route_match.begin(0), skip_ranges)
          pos = route_match.end(0)
        else
          route_path = route_match[2]
          full_path = build_full_path(prefix, route_path)
          route_line = base_line + newline_count_before(content, route_match.begin(0))
          params = extract_brace_path_params(full_path)
          details = Details.new(PathInfo.new(file_path, route_line))
          endpoints << Endpoint.new(full_path, "GET", params, details.dup)
          pos = route_match.end(0)
        end
      end

      chained_static_route_regex = /Route::((?:\w+\s*\([^;]*?\)\s*->\s*)+)(view|redirect|permanentRedirect)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      while route_match = content.match(chained_static_route_regex, pos)
        if inside_laravel_group_body?(route_match.begin(0), route_groups) ||
           inside_php_skip_range?(route_match.begin(0), skip_ranges)
          pos = route_match.end(0)
        else
          route_prefix = extract_group_prefix("Route::#{route_match[1]}")
          route_path = route_match[3]
          full_path = build_full_path(build_full_path(prefix, route_prefix), route_path)
          route_line = base_line + newline_count_before(content, route_match.begin(0))
          params = extract_brace_path_params(full_path)
          details = Details.new(PathInfo.new(file_path, route_line))
          endpoints << Endpoint.new(full_path, "GET", params, details.dup)
          pos = route_match.end(0)
        end
      end

      # 2. Resource routes
      resource_calls = extract_resource_route_calls(content, "resource", skip_ranges, lexer)
      resource_calls.each do |call|
        next if inside_laravel_group_body?(call.start_pos, route_groups) ||
                inside_php_skip_range?(call.start_pos, skip_ranges)

        resource_name = call.resource
        route_line = base_line + newline_count_before(content, call.start_pos)
        actions = resource_actions_for_statement(call.statement, api: false)
        parameter_overrides = resource_parameter_overrides_for_statement(call.statement)
        endpoints.concat(create_resource_endpoints(prefix, resource_name, file_path, route_line, actions, parameter_overrides, call.statement, include_callee, imports, resource_controller_cache))
      end

      api_resource_calls = extract_resource_route_calls(content, "apiResource", skip_ranges, lexer)
      api_resource_calls.each do |call|
        next if inside_laravel_group_body?(call.start_pos, route_groups) ||
                inside_php_skip_range?(call.start_pos, skip_ranges)

        resource_name = call.resource
        route_line = base_line + newline_count_before(content, call.start_pos)
        actions = resource_actions_for_statement(call.statement, api: true)
        parameter_overrides = resource_parameter_overrides_for_statement(call.statement)
        endpoints.concat(create_api_resource_endpoints(prefix, resource_name, file_path, route_line, actions, parameter_overrides, call.statement, include_callee, imports, resource_controller_cache))
      end

      # 3. Group routes (recursive). Extract group bodies before scanning nested
      # routes so prefixed groups do not also emit unprefixed endpoints.
      route_groups.each do |group|
        new_prefix = group.prefix.empty? ? prefix : build_full_path(prefix, group.prefix)
        group_base_line = base_line + newline_count_before(content, group.body_start)
        endpoints.concat(analyze_routes_content(group.body, new_prefix, file_path, include_callee, group_base_line, imports))
      end

      endpoints
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

    private def newline_count_before(content : String, pos : Int32) : Int32
      return 0 if pos <= 0

      content[0...pos].count('\n')
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

    private def create_resource_endpoints(prefix : String,
                                          resource : String,
                                          file_path : String,
                                          line : Int32? = nil,
                                          actions : Array(String) = RESOURCE_ACTIONS,
                                          parameter_overrides : Hash(String, String) = EMPTY_RESOURCE_PARAMS,
                                          statement : String? = nil,
                                          include_callee : Bool = false,
                                          imports : Hash(String, String) = EMPTY_IMPORTS,
                                          controller_cache : Hash(String, ControllerActionMap?) = {} of String => ControllerActionMap?) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path, line))

      # Standard Laravel resource routes
      resource_routes = resource_route_templates(prefix, resource, parameter_overrides, api: false)

      resource_routes.each do |route_info|
        action = route_info.action
        path = route_info.path
        method = route_info.method
        next unless actions.includes?(action)

        params = extract_brace_path_params(path)
        endpoint = Endpoint.new(path, method, params, details)
        attach_resource_action_callees(endpoint, statement, action, file_path, imports, controller_cache) if include_callee && statement
        endpoints << endpoint
      end

      endpoints
    end

    private def create_api_resource_endpoints(prefix : String,
                                              resource : String,
                                              file_path : String,
                                              line : Int32? = nil,
                                              actions : Array(String) = API_RESOURCE_ACTIONS,
                                              parameter_overrides : Hash(String, String) = EMPTY_RESOURCE_PARAMS,
                                              statement : String? = nil,
                                              include_callee : Bool = false,
                                              imports : Hash(String, String) = EMPTY_IMPORTS,
                                              controller_cache : Hash(String, ControllerActionMap?) = {} of String => ControllerActionMap?) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path, line))

      # API resource routes (excludes create and edit forms)
      api_resource_routes = resource_route_templates(prefix, resource, parameter_overrides, api: true)

      api_resource_routes.each do |route_info|
        action = route_info.action
        path = route_info.path
        method = route_info.method
        next unless actions.includes?(action)

        params = extract_brace_path_params(path)
        endpoint = Endpoint.new(path, method, params, details)
        attach_resource_action_callees(endpoint, statement, action, file_path, imports, controller_cache) if include_callee && statement
        endpoints << endpoint
      end

      endpoints
    end

    RESOURCE_ACTIONS     = ["index", "create", "store", "show", "edit", "update", "destroy"]
    API_RESOURCE_ACTIONS = ["index", "store", "show", "update", "destroy"]

    private def resource_route_templates(prefix : String, resource : String, parameter_overrides : Hash(String, String), api : Bool) : Array(ResourceEndpointTemplate)
      collection_path = resource_collection_path(prefix, resource, parameter_overrides)
      param_name = resource_param_name_for_segment(resource_segments(resource).last, parameter_overrides)
      member_path = "#{collection_path}/{#{param_name}}"
      templates = [
        ResourceEndpointTemplate.new("index", collection_path, "GET"),
        ResourceEndpointTemplate.new("store", collection_path, "POST"),
        ResourceEndpointTemplate.new("show", member_path, "GET"),
        ResourceEndpointTemplate.new("update", member_path, "PUT"),
        ResourceEndpointTemplate.new("update", member_path, "PATCH"),
        ResourceEndpointTemplate.new("destroy", member_path, "DELETE"),
      ]

      unless api
        templates.insert(1, ResourceEndpointTemplate.new("create", "#{collection_path}/create", "GET"))
        templates.insert(4, ResourceEndpointTemplate.new("edit", "#{member_path}/edit", "GET"))
      end

      templates
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

    private def extract_resource_route_calls(content : String,
                                             method_name : String,
                                             skip_ranges : Array(Range(Int32, Int32)),
                                             lexer : Noir::PhpLexer) : Array(ResourceRouteCall)
      calls = [] of ResourceRouteCall
      regex = Regex.new("Route::#{method_name}\\s*\\(\\s*['\"]([^'\"]+)['\"]", Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE)
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

    private def resource_actions_for_statement(statement : String, api : Bool) : Array(String)
      actions = api ? API_RESOURCE_ACTIONS.dup : RESOURCE_ACTIONS.dup

      if only = extract_resource_action_filter(statement, "only")
        return actions.select { |action| only.includes?(action) }
      end

      if except = extract_resource_action_filter(statement, "except")
        return actions.reject { |action| except.includes?(action) }
      end

      actions
    end

    private def extract_resource_action_filter(statement : String, filter_name : String) : Array(String)?
      match = statement.match(Regex.new("->\\s*#{filter_name}\\s*\\((.*?)\\)", Regex::Options::IGNORE_CASE | Regex::Options::MULTILINE))
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
