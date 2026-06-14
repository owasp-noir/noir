require "../../engines/php_engine"

module Analyzer::Php
  class CakePHP < PhpEngine
    @method_def_regexes = Hash(String, Regex).new

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Analyze CakePHP routes file. Require a real `.php` extension so a Bake
      # code-generation template (`.../config/routes.php.twig`) — whose body is
      # full of unrendered `{{ plugin }}` placeholders — isn't mistaken for a
      # routes file by the `config/routes.php` substring match.
      if path.includes?("config/routes.php") && path.ends_with?(".php")
        endpoints.concat(analyze_routes_file(path))
      end

      endpoints
    end

    private def analyze_routes_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      begin
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end
          endpoints = analyze_routes_content(content, "", path, include_callee)
        end
      rescue e
        logger.debug "Error analyzing routes file #{path}: #{e}"
      end
      endpoints
    end

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      # `scope()`/`prefix()`/`plugin()` each open a nested RouteBuilder whose
      # routes inherit a URL prefix. Extract their bodies first so the verb
      # scans below don't emit nested routes a second time without the prefix.
      scopes = extract_scopes(content)

      # 1. Connect routes. Capture the whole statement (up to the terminating
      # `;`) so the chained method restriction is visible. Modern CakePHP pins
      # verbs with `->setMethods(['POST'])`, not the legacy
      # `'_method' => 'POST'` option, so the previous options-only scan
      # recorded every connect route as GET — turning real POST/PUT/DELETE
      # endpoints into GET false positives (and dropping the verbs they
      # actually answer).
      pos = 0
      while route_match = content.match(CONNECT_REGEX, pos)
        if inside_scope_body?(route_match.begin(0), scopes)
          pos = route_match.end(0)
          next
        end

        route_path = route_match[2]
        statement = route_match[3]
        options_str = first_bracket_group(statement)

        full_path = build_full_path(prefix, route_path)
        target = extract_controller_action_target(options_str)
        methods = extract_connect_methods(statement, options_str)

        methods.each do |method|
          params = extract_route_params(full_path)
          endpoint = Endpoint.new(full_path, method, params, details.dup)
          attach_route_target_callees(endpoint, target, file_path) if include_callee
          endpoints << endpoint
        end
        pos = route_match.end(0)
      end

      # 2. HTTP verb shortcuts: $routes->get/post/..., Router::get/...
      VERB_REGEXES.each do |method, pattern|
        pos = 0
        while route_match = content.match(pattern, pos)
          if inside_scope_body?(route_match.begin(0), scopes)
            pos = route_match.end(0)
            next
          end

          route_path = route_match[2]
          full_path = build_full_path(prefix, route_path)
          params = extract_route_params(full_path)
          target = extract_controller_action_target(route_match[3]?)
          endpoint = Endpoint.new(full_path, method, params, details.dup)
          attach_route_target_callees(endpoint, target, file_path) if include_callee
          endpoints << endpoint
          pos = route_match.end(0)
        end
      end

      # 3. Resource routes
      pos = 0
      while route_match = content.match(RESOURCE_REGEX, pos)
        if inside_scope_body?(route_match.begin(0), scopes)
          pos = route_match.end(0)
          next
        end

        resource_name = route_match[2]
        full_resource_path = build_full_path(prefix, resource_name)
        endpoints.concat(create_resource_endpoints(full_resource_path, file_path, include_callee, resource_name))
        pos = route_match.end(0)
      end

      # 4. Recurse into each scope/prefix/plugin body with its prefix applied.
      scopes.each do |scope|
        new_prefix = build_full_path(prefix, scope.prefix)
        endpoints.concat(analyze_routes_content(scope.body, new_prefix, file_path, include_callee))
      end

      endpoints
    end

    private struct Scope
      getter prefix, body, body_start, body_end

      def initialize(@prefix : String, @body : String, @body_start : Int32, @body_end : Int32)
      end
    end

    # Route receivers in a CakePHP routes file: the injected builder under any
    # variable name (`$routes`, `$builder`, `$routeBuilder`, ...) or the static
    # `Router` facade used by older apps and plugin route files (croogo).
    CONNECT_REGEX    = /(\$\w+|Router)(?:->|::)connect\s*\(\s*['"]([^'"]+)['"](.*?);/mi
    RESOURCE_REGEX   = /(\$\w+|Router)(?:->|::)resources\s*\(\s*['"]([^'"]+)['"]/mi
    SCOPE_OPEN_REGEX = /(?:\$\w+|Router)(?:->|::)(scope|prefix|plugin)\s*\(/mi
    VERB_REGEXES     = {
      "GET"     => /(\$\w+|Router)(?:->|::)get\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
      "POST"    => /(\$\w+|Router)(?:->|::)post\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
      "PUT"     => /(\$\w+|Router)(?:->|::)put\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
      "PATCH"   => /(\$\w+|Router)(?:->|::)patch\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
      "DELETE"  => /(\$\w+|Router)(?:->|::)delete\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
      "OPTIONS" => /(\$\w+|Router)(?:->|::)options\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
      "HEAD"    => /(\$\w+|Router)(?:->|::)head\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*\[(.*?)\])?/mi,
    }

    # Find top-level scope/prefix/plugin closures and their bodies. Advancing
    # past each matched body means nested scopes are not captured here — they
    # surface when `analyze_routes_content` recurses into the body — so a route
    # is never emitted twice.
    private def extract_scopes(content : String) : Array(Scope)
      scopes = [] of Scope
      pos = 0

      while open_match = content.match(SCOPE_OPEN_REGEX, pos)
        method = open_match[1].downcase
        info = parse_scope_call(content, open_match.end(0), method)
        if info
          prefix, body, body_start, body_end = info
          scopes << Scope.new(prefix, body, body_start, body_end)
          pos = body_end + 1
        else
          pos = open_match.end(0)
        end
      end

      scopes
    end

    private def parse_scope_call(content : String, pos : Int32, method : String) : Tuple(String, String, Int32, Int32)?
      return unless pos < content.size

      context = content[pos..]
      closure = context.match(/(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?\{/mi)
      return unless closure

      prelude = context[0...closure.begin(0)]
      brace_pos = pos + closure.end(0) - 1
      body_end = find_matching_php_close_brace(content, brace_pos)
      return unless body_end

      {scope_prefix_from_prelude(prelude, method), content[(brace_pos + 1)...body_end], brace_pos + 1, body_end}
    end

    # Resolve the URL prefix a scope/prefix/plugin contributes. `scope`/`prefix`
    # take the path as their first string argument; `plugin` takes the plugin
    # name, with the mounted path supplied separately as a `'path' => '/x'`
    # option (falling back to the dasherized plugin name).
    private def scope_prefix_from_prelude(prelude : String, method : String) : String
      if method == "plugin"
        if path = prelude.match(/['"]path['"]\s*=>\s*['"]([^'"]*)['"]/i)
          return path[1]
        end
        name = prelude.match(/['"]([^'"]+)['"]/)
        return name ? "/#{name[1].downcase}" : ""
      end

      # `prefix('v10', ['path' => '/v1.0'], ...)` mounts under the explicit
      # `path` option, NOT the dasherized prefix name — honour it like `plugin`
      # does (`scope('/api', ...)` has no such option, so it falls through to
      # its first string arg, the path itself).
      if method == "prefix"
        if path = prelude.match(/['"]path['"]\s*=>\s*['"]([^'"]*)['"]/i)
          return path[1]
        end
      end

      first = prelude.match(/['"]([^'"]*)['"]/)
      first ? first[1] : ""
    end

    private def inside_scope_body?(pos : Int32, scopes : Array(Scope)) : Bool
      scopes.any? { |scope| pos >= scope.body_start && pos < scope.body_end }
    end

    # Determine the HTTP verbs a `connect()` route answers. Prefer the
    # chained `->setMethods([...])` (modern CakePHP), fall back to the
    # legacy `'_method' => '...'` option, and default to GET when neither
    # is present (an unrestricted `connect()` is most commonly reached via
    # GET in these apps).
    private def extract_connect_methods(statement : String, options_str : String?) : Array(String)
      if set_methods = statement.match(/->\s*setMethods\s*\(\s*\[([^\]]*)\]/i)
        methods = extract_methods_from_array(set_methods[1])
        return methods unless methods.empty?
      end

      if options_str && (legacy = options_str.match(/['"]_method['"]\s*=>\s*['"]([^'"]+)['"]/i))
        return [legacy[1].upcase]
      end

      ["GET"]
    end

    private def extract_methods_from_array(array_body : String) : Array(String)
      methods = [] of String
      array_body.scan(/['"]([^'"]+)['"]/).each do |match|
        methods << match[1].upcase
      end
      methods
    end

    # First `[...]` group in a connect statement — the route options array
    # carrying `controller`/`action`. `setPass`/`setMethods` arrays follow it.
    private def first_bracket_group(statement : String) : String?
      match = statement.match(/\[(.*?)\]/m)
      match ? match[1] : nil
    end

    # CakePHP supports both `{id}` and `:id` route params; the latter is not
    # covered by the engine helper.
    private def extract_route_params(route_path : String) : Array(Param)
      params = extract_brace_path_params(route_path)
      route_path.scan(/:(\w+)/).each do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def create_resource_endpoints(resource_path : String,
                                          file_path : String,
                                          include_callee : Bool,
                                          controller_name : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      # Standard REST resource routes
      resource_routes = [
        {resource_path, "GET", "index"},
        {resource_path, "POST", "add"},
        {"#{resource_path}/{id}", "GET", "view"},
        {"#{resource_path}/{id}", "PUT", "edit"},
        {"#{resource_path}/{id}", "PATCH", "edit"},
        {"#{resource_path}/{id}", "DELETE", "delete"},
      ]

      resource_routes.each do |route_info|
        path, method, action = route_info
        params = extract_route_params(path)
        endpoint = Endpoint.new(path, method, params, details.dup)
        attach_route_target_callees(endpoint, {controller_name, action}, file_path) if include_callee
        endpoints << endpoint
      end

      endpoints
    end

    private def attach_route_target_callees(endpoint : Endpoint,
                                            target : Tuple(String, String)?,
                                            routes_file_path : String)
      return unless target

      method_body = extract_controller_action_body(routes_file_path, target[0], target[1])
      return unless method_body

      body, controller_path, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, controller_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_controller_action_body(routes_file_path : String,
                                               controller_name : String,
                                               action_name : String) : Tuple(String, String, Int32)?
      controller_path = resolve_cakephp_controller_path(routes_file_path, controller_name)
      return unless controller_path && File.exists?(controller_path)

      content = read_file_content(controller_path)
      # Memoized: an interpolated regex literal recompiles (PCRE2 JIT) on
      # every evaluation, and action names repeat across controllers.
      method_regex = @method_def_regexes[action_name] ||= /(?:public|protected|private)\s+(?:static\s+)?function\s+#{action_name}\s*\(/
      method_match = content.match(method_regex)
      return unless method_match

      method_body = extract_php_method_body_after(content, method_match.begin(0))
      return unless method_body

      body, start_line = method_body
      {body, controller_path, start_line}
    rescue e
      logger.debug "Error resolving CakePHP handler #{controller_name}::#{action_name}: #{e}"
      nil
    end

    private def extract_controller_action_target(options_str : String?) : Tuple(String, String)?
      return unless options_str

      controller_match = options_str.match(/['"]controller['"]\s*=>\s*['"]([^'"]+)['"]/)
      action_match = options_str.match(/['"]action['"]\s*=>\s*['"]([^'"]+)['"]/)
      return unless controller_match && action_match

      controller_name = controller_match[1].strip
      action_name = action_match[1].strip
      return if controller_name.empty? || action_name.empty?
      return unless action_name.match(/\A[A-Za-z_]\w*\z/)

      {controller_name, action_name}
    end

    private def resolve_cakephp_controller_path(routes_file_path : String, controller_name : String) : String?
      marker = "/config/routes.php"
      marker_index = routes_file_path.index(marker)
      return unless marker_index

      relative = cakephp_controller_relative_path(controller_name)
      return unless relative

      File.join(routes_file_path[0...marker_index], "src", "Controller", "#{relative}.php")
    end

    private def cakephp_controller_relative_path(controller_name : String) : String?
      normalized = controller_name.gsub("\\", "/").strip
      segments = normalized.split("/").reject(&.empty?)
      return if segments.empty?
      return if segments.any? { |segment| segment == "." || segment == ".." }

      last_index = segments.size - 1
      last_segment = normalize_controller_segment(segments[last_index])
      return if last_segment.empty?

      segments[last_index] = last_segment.ends_with?("Controller") ? last_segment : "#{last_segment}Controller"
      File.join(segments)
    end

    private def normalize_controller_segment(segment : String) : String
      base = segment.strip
      suffix = "Controller"
      base = base[0...(base.size - suffix.size)] if base.ends_with?(suffix)
      return base if base.match(/[A-Z]/) && !base.includes?("_") && !base.includes?("-")

      String.build do |io|
        base.split(/[_-]/).each do |part|
          next if part.empty?

          io << part[0].upcase
          io << part[1..] if part.size > 1
        end
      end
    end
  end
end
