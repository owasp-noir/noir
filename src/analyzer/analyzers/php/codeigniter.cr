require "../../engines/php_engine"

module Analyzer::Php
  class CodeIgniter < PhpEngine
    @method_def_regexes = Hash(String, Regex).new

    # CI4 placeholders → param names. CI3 uses the same shapes.
    PLACEHOLDER_MAP = {
      "any"      => "any",
      "segment"  => "segment",
      "num"      => "num",
      "alpha"    => "alpha",
      "alphanum" => "alphanum",
      "hash"     => "hash",
    }

    ALL_HTTP_VERBS = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
    CI3_VERBS      = %w[get post put patch delete options head cli]

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      return endpoints unless path.ends_with?(".php")

      # CI4: app/Config/Routes.php  |  CI3: application/config/routes.php
      if path.includes?("Config/Routes.php") || path.includes?("application/config/routes.php")
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
          endpoints.concat(analyze_routes_content(content, "", path, include_callee, "App\\Controllers"))
          endpoints.concat(analyze_ci3_routes(content, path))
        end
      rescue e
        logger.debug "Error analyzing routes file #{path}: #{e}"
      end
      endpoints
    end

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool,
                                       controller_namespace : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      working_content = content

      # 1. Group routes: $routes->group('prefix', [opts]?, function($routes) { ... })
      # Match only the header up to the opening `{`, then balance braces with the
      # engine's matcher. The old fixed-depth regex silently failed on 4+ levels
      # of brace nesting, so inner routes lost the group prefix entirely.
      group_header = /\$routes->group\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*(\[(?:[^\[\]]|\[[^\[\]]*\])*\]))?\s*,\s*(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?\{/mi
      loop do
        match = working_content.match(group_header)
        break unless match
        start = match.begin(0) || 0
        brace_pos = start + match[0].size - 1 # index of the opening '{'
        close = find_matching_php_close_brace(working_content, brace_pos)
        unless close
          # Unbalanced/truncated source: drop just the header to avoid looping.
          working_content = working_content[0...start] + working_content[(start + match[0].size)..]
          next
        end
        group_prefix = normalize_route(match[1])
        group_options = match[2]?
        group_content = working_content[(brace_pos + 1)...close]
        group_namespace = extract_group_namespace(group_options) || controller_namespace
        new_prefix = build_full_path(prefix, group_prefix)
        endpoints.concat(analyze_routes_content(group_content, new_prefix, file_path, include_callee, group_namespace))
        # Strip the entire group call (through its closing brace) so step 3+ never re-scans it.
        working_content = working_content[0...start] + working_content[(close + 1)..]
      end

      # 2. Environment routes: $routes->environment('env', function($routes) { ... }) — preserve prefix
      env_header = /\$routes->environment\s*\(\s*['"][^'"]+['"]\s*,\s*(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?\{/mi
      loop do
        match = working_content.match(env_header)
        break unless match
        start = match.begin(0) || 0
        brace_pos = start + match[0].size - 1
        close = find_matching_php_close_brace(working_content, brace_pos)
        unless close
          working_content = working_content[0...start] + working_content[(start + match[0].size)..]
          next
        end
        env_content = working_content[(brace_pos + 1)...close]
        endpoints.concat(analyze_routes_content(env_content, prefix, file_path, include_callee, controller_namespace))
        working_content = working_content[0...start] + working_content[(close + 1)..]
      end

      # 3. HTTP verb routes: $routes->get/post/put/patch/delete/options/head('path', ...)
      verb_pattern = /\$routes->(get|post|put|patch|delete|options|head)\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*(.*?))?\s*\)/mi
      working_content.scan(verb_pattern).each do |match|
        method = match[1].upcase
        route_path = match[2]
        handler = extract_ci4_handler(match[3]?)
        full_path = build_full_path(prefix, normalize_route(route_path))
        params = extract_ci_path_params(full_path)
        endpoint = Endpoint.new(full_path, method, params, details.dup)
        attach_route_target_callees(endpoint, handler, file_path, controller_namespace) if include_callee
        endpoints << endpoint
      end

      # 4. $routes->match(['get','post'], 'path', ...)
      match_pattern = /\$routes->match\s*\(\s*\[([^\]]+)\]\s*,\s*['"]([^'"]+)['"](?:\s*,\s*(.*?))?\s*\)/mi
      working_content.scan(match_pattern).each do |match|
        methods = extract_methods_from_array(match[1])
        route_path = match[2]
        handler = extract_ci4_handler(match[3]?)
        full_path = build_full_path(prefix, normalize_route(route_path))
        params = extract_ci_path_params(full_path)
        methods.each do |http_method|
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_route_target_callees(endpoint, handler, file_path, controller_namespace) if include_callee
          endpoints << endpoint
        end
      end

      # 5. $routes->add('path', ...) — any HTTP verb
      add_pattern = /\$routes->add\s*\(\s*['"]([^'"]+)['"](?:\s*,\s*(.*?))?\s*\)/mi
      working_content.scan(add_pattern).each do |match|
        route_path = match[1]
        handler = extract_ci4_handler(match[2]?)
        full_path = build_full_path(prefix, normalize_route(route_path))
        params = extract_ci_path_params(full_path)
        ALL_HTTP_VERBS.each do |http_method|
          endpoint = Endpoint.new(full_path, http_method, params, details.dup)
          attach_route_target_callees(endpoint, handler, file_path, controller_namespace) if include_callee
          endpoints << endpoint
        end
      end

      # 6. $routes->resource('photos', ...) — RESTful API resource
      resource_pattern = /\$routes->resource\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi
      working_content.scan(resource_pattern).each do |match|
        full_resource_path = build_full_path(prefix, normalize_route(match[1]))
        endpoints.concat(create_resource_endpoints(full_resource_path, file_path))
      end

      # 7. $routes->presenter('photos', ...) — controller-style HTML resource
      presenter_pattern = /\$routes->presenter\s*\(\s*['"]([^'"]+)['"][^)]*\)/mi
      working_content.scan(presenter_pattern).each do |match|
        full_resource_path = build_full_path(prefix, normalize_route(match[1]))
        endpoints.concat(create_presenter_endpoints(full_resource_path, file_path))
      end

      endpoints
    end

    private def attach_route_target_callees(endpoint : Endpoint,
                                            handler : String?,
                                            routes_file_path : String,
                                            controller_namespace : String)
      method_body = extract_handler_method_body(routes_file_path, handler, controller_namespace)
      return unless method_body

      body, controller_path, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, controller_path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_handler_method_body(routes_file_path : String,
                                            handler : String?,
                                            controller_namespace : String) : Tuple(String, String, Int32)?
      target = parse_ci4_handler(handler)
      return unless target

      controller_name, action_name = target
      controller_path = resolve_ci4_controller_path(routes_file_path, controller_name, controller_namespace)
      return unless controller_path && File.exists?(controller_path)

      content = read_file_content(controller_path)
      # Memoized: an interpolated regex literal recompiles (PCRE2 JIT) on
      # every evaluation, and action names repeat across controllers.
      method_regex = @method_def_regexes[action_name] ||= /(?:public|protected|private)\s+function\s+#{action_name}\s*\(/
      method_match = content.match(method_regex)
      return unless method_match

      method_body = extract_php_method_body_after(content, method_match.begin(0))
      return unless method_body

      body, start_line = method_body
      {body, controller_path, start_line}
    rescue e
      logger.debug "Error resolving CodeIgniter handler #{handler}: #{e}"
      nil
    end

    private def extract_group_namespace(options : String?) : String?
      return unless options

      if namespace_match = options.match(/['"]namespace['"]\s*=>\s*['"]([^'"]+)['"]/)
        namespace_match[1]
      end
    end

    private def extract_ci4_handler(argument : String?) : String?
      return unless argument

      handler = argument.strip
      if string_match = handler.match(/\A['"]([^'"]+)['"]/)
        return string_match[1]
      end

      if array_match = handler.match(/\A\[\s*([^,\]]+)\s*,\s*['"]([^'"]+)['"]/)
        controller_expr = array_match[1].strip
        action_name = array_match[2]
        if class_match = controller_expr.match(/\A((?:\\?[A-Za-z_]\w*\\)*\\?[A-Za-z_]\w*)::class\z/)
          "#{class_match[1]}::#{action_name}"
        end
      end
    end

    private def parse_ci4_handler(handler : String?) : Tuple(String, String)?
      return unless handler

      target = handler.split("/", 2)[0].strip
      parts = target.split("::", 2)
      return unless parts.size == 2

      controller_name = parts[0].strip
      action_name = parts[1].strip
      return if controller_name.empty?
      return unless action_name.match(/\A[A-Za-z_]\w*\z/)

      {controller_name, action_name}
    end

    private def resolve_ci4_controller_path(routes_file_path : String,
                                            controller_name : String,
                                            controller_namespace : String) : String?
      marker = "/app/Config/Routes.php"
      marker_index = routes_file_path.index(marker)
      return unless marker_index

      controller_root = File.join(routes_file_path[0...marker_index], "app", "Controllers")
      full_controller = controller_name.includes?("\\") ? controller_name : "#{controller_namespace}\\#{controller_name}"
      relative = full_controller.gsub("\\", "/")
      relative = relative.sub(/\A\/+/, "")
      relative = relative.sub(/\AApp\/Controllers\/?/, "")
      return if relative.empty? || relative.includes?("..")

      File.join(controller_root, "#{relative}.php")
    end

    # CodeIgniter 3 style: $route['products/(:num)'] = 'catalog/lookup/$1';
    # Optional method qualifier via array: $route['products']['post'] = '...'
    private def analyze_ci3_routes(content : String, file_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(file_path))

      content.scan(/\$route\s*\[\s*['"]([^'"]+)['"]\s*\](?:\s*\[\s*['"]([^'"]+)['"]\s*\])?\s*=\s*['"]([^'"]+)['"]/mi).each do |match|
        route_path = match[1]
        method_qualifier = match[2]?

        # Skip CI3 reserved config keys
        next if route_path == "default_controller" || route_path == "404_override" ||
                route_path == "translate_uri_dashes"

        # Only treat the second [...] as an HTTP verb when it's actually one;
        # CI3 also uses keys like ['namespace'] or ['hostname'] for non-method config.
        methods = if method_qualifier && CI3_VERBS.includes?(method_qualifier.downcase)
                    [method_qualifier.upcase]
                  else
                    # Bare $route['x'] = '...' matches any HTTP verb.
                    ALL_HTTP_VERBS
                  end

        normalized = normalize_route(route_path)
        params = extract_ci_path_params(normalized)
        methods.each do |http_method|
          endpoints << Endpoint.new(normalized, http_method, params, details.dup)
        end
      end

      endpoints
    end

    # CI4 default RESTful API resource routes
    private def create_resource_endpoints(resource_path : String, file_path : String) : Array(Endpoint)
      details = Details.new(PathInfo.new(file_path))
      base = resource_path.starts_with?("/") ? resource_path : "/#{resource_path}"

      resource_routes = [
        {base, "GET"},                # index
        {"#{base}/new", "GET"},       # new
        {base, "POST"},               # create
        {"#{base}/{id}", "GET"},      # show
        {"#{base}/{id}/edit", "GET"}, # edit
        {"#{base}/{id}", "PUT"},      # update
        {"#{base}/{id}", "PATCH"},    # update
        {"#{base}/{id}", "DELETE"},   # delete
      ]

      resource_routes.map do |route_info|
        path, method = route_info
        params = extract_ci_path_params(path)
        Endpoint.new(path, method, params, details.dup)
      end
    end

    # CI4 presenter (HTML form) resource routes
    private def create_presenter_endpoints(resource_path : String, file_path : String) : Array(Endpoint)
      details = Details.new(PathInfo.new(file_path))
      base = resource_path.starts_with?("/") ? resource_path : "/#{resource_path}"

      presenter_routes = [
        {base, "GET"},                   # index
        {"#{base}/show/{id}", "GET"},    # show
        {"#{base}/new", "GET"},          # new
        {"#{base}/create", "POST"},      # create
        {"#{base}/edit/{id}", "GET"},    # edit
        {"#{base}/update/{id}", "POST"}, # update
        {"#{base}/remove/{id}", "GET"},  # remove
        {"#{base}/delete/{id}", "POST"}, # delete
      ]

      presenter_routes.map do |route_info|
        path, method = route_info
        params = extract_ci_path_params(path)
        Endpoint.new(path, method, params, details.dup)
      end
    end

    # Convert CI placeholders to braces:
    #   /users/(:num)     -> /users/{num}
    #   /files/(:any)     -> /files/{any}
    #   /post/(:segment)  -> /post/{segment}
    private def normalize_route(route_path : String) : String
      normalized = route_path.gsub(/\(:(\w+)\)/) do |_match|
        token = $1
        name = PLACEHOLDER_MAP.fetch(token, token)
        "{#{name}}"
      end
      normalized.starts_with?("/") ? normalized : "/#{normalized}"
    end

    # Extract path params, deduplicating by appending positional suffixes when
    # the same placeholder name appears multiple times (e.g. /a/{any}/b/{any}).
    private def extract_ci_path_params(route_path : String) : Array(Param)
      params = [] of Param
      counts = Hash(String, Int32).new(0)
      route_path.scan(/\{(\w+)\}/) do |match|
        name = match[1]
        counts[name] += 1
        param_name = counts[name] > 1 ? "#{name}#{counts[name]}" : name
        params << Param.new(param_name, "", "path")
      end
      params
    end

    private def extract_methods_from_array(methods_str : String) : Array(String)
      methods = [] of String
      methods_str.scan(/['"]([^'"]+)['"]/) do |match|
        methods << match[1].upcase
      end
      methods
    end
  end
end
