require "../../engines/php_engine"

module Analyzer::Php
  class ThinkPHP < PhpEngine
    ALL_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]

    @method_def_regexes = Hash(String, Regex).new

    private struct RouteGroup
      getter prefix, body, body_start, body_end

      def initialize(@prefix : String, @body : String, @body_start : Int32, @body_end : Int32)
      end
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")

      is_route = path.includes?("route/") || File.basename(path) == "route.php"
      is_controller = path.includes?("controller/")

      # PERFORMANCE OPTIMIZATION: Skip opening, reading, and parsing files that are
      # neither explicit route definitions nor implicit controller classes.
      return endpoints unless is_route || is_controller

      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # 1. Explicit Route definitions
        if is_route
          # Determine base prefix from multi-app route files (e.g. app/shop/route/app.php -> prefix is "/shop")
          base_prefix = ""
          if path.includes?("app/") || path.includes?("application/")
            segments = path.split('/')
            route_idx = segments.index("route")
            if route_idx && route_idx > 1
              parent = segments[route_idx - 1]
              if parent != "app" && parent != "application"
                base_prefix = "/" + camel_to_snake(parent)
              end
            end
          end

          endpoints.concat(analyze_routes_content(content, base_prefix, path, include_callee))
        end

        # 2. Implicit Controller auto-routing
        if is_controller
          endpoints.concat(analyze_controller(path, content, include_callee))
          endpoints.concat(analyze_annotation_routes(path, content, include_callee))
        end
      end

      endpoints
    end

    private def analyze_routes_content(content : String,
                                       prefix : String,
                                       file_path : String,
                                       include_callee : Bool,
                                       base_line : Int32 = 1) : Array(Endpoint)
      endpoints = [] of Endpoint
      route_groups = extract_route_groups(content)

      # 1. Standard verb routes: Route::get('pattern', 'handler')
      verb_regex = /Route::(get|post|put|delete|patch|any)\s*\(\s*['"]([^'"]+)['"]\s*,/mi
      pos = 0
      loop do
        route_match = content.match(verb_regex, pos)
        break unless route_match

        if inside_group_body?(route_match.begin(0), route_groups)
          pos = route_match.end(0)
          next
        end

        verb = route_match[1].upcase
        route_path = route_match[2]
        full_path = build_full_path(prefix, route_path)
        normalized_path = normalize_route(full_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))

        methods = verb == "ANY" ? ALL_METHODS : [verb]

        handler_body, next_pos, body_start_line = extract_inline_closure_body(content, route_match.end(0), base_line)
        route_handler = handler_body ? nil : extract_route_handler(content, route_match.end(0))

        path_params = extract_path_params(full_path)
        handler_params = handler_body ? extract_request_params(handler_body) : [] of Param

        methods.each do |m|
          params = path_params.dup
          params.concat(handler_params)
          params = dedup_params(params)

          details = Details.new(PathInfo.new(file_path, route_line))
          endpoint = Endpoint.new(normalized_path, m, params, details)
          attach_route_callees(endpoint, handler_body, file_path, body_start_line, route_handler) if include_callee
          endpoints << endpoint
        end

        pos = next_pos > pos ? next_pos : route_match.end(0)
      end

      # 2. Generic Route::rule('pattern', 'handler', 'methods')
      rule_regex = /Route::rule\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*(?:,\s*['"]([^'"]+)['"])?/mi
      pos = 0
      loop do
        route_match = content.match(rule_regex, pos)
        break unless route_match

        if inside_group_body?(route_match.begin(0), route_groups)
          pos = route_match.end(0)
          next
        end

        route_path = route_match[1]
        full_path = build_full_path(prefix, route_path)
        normalized_path = normalize_route(full_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))

        methods = ["GET"]
        if method_str = route_match[3]?
          methods = extract_methods_from_string(method_str)
        end

        path_params = extract_path_params(full_path)

        methods.each do |m|
          details = Details.new(PathInfo.new(file_path, route_line))
          endpoints << Endpoint.new(normalized_path, m, path_params.dup, details)
        end

        pos = route_match.end(0)
      end

      # 3. Route::resource('pattern', 'controller')
      resource_regex = /Route::resource\s*\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]/mi
      pos = 0
      loop do
        route_match = content.match(resource_regex, pos)
        break unless route_match

        if inside_group_body?(route_match.begin(0), route_groups)
          pos = route_match.end(0)
          next
        end

        route_path = route_match[1]
        full_path = build_full_path(prefix, route_path)
        route_line = base_line + newline_count_before(content, route_match.begin(0))

        endpoints.concat(generate_resource_endpoints(full_path, file_path, route_line))
        pos = route_match.end(0)
      end

      # 4. Recurse into groups
      route_groups.each do |group|
        new_prefix = group.prefix.empty? ? prefix : build_full_path(prefix, group.prefix)
        group_base_line = base_line + newline_count_before(content, group.body_start)
        endpoints.concat(analyze_routes_content(group.body, new_prefix, file_path, include_callee, group_base_line))
      end

      endpoints
    end

    private def extract_route_groups(content : String) : Array(RouteGroup)
      groups = [] of RouteGroup
      group_regex = /Route::group\s*\(\s*['"]([^'"]*)['"]\s*,\s*(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?\{/mi
      pos = 0

      loop do
        group_match = content.match(group_regex, pos)
        break unless group_match

        brace_pos = group_match.end(0) - 1 # opening '{'
        body_end = find_matching_php_close_brace(content, brace_pos)
        if body_end
          prefix = group_match[1]
          body = content[(brace_pos + 1)...body_end]
          groups << RouteGroup.new(prefix, body, brace_pos + 1, body_end)
          pos = body_end + 1
        else
          pos = group_match.end(0)
        end
      end

      groups
    end

    private def generate_resource_endpoints(prefix : String, file_path : String, line : Int32) : Array(Endpoint)
      endpoints = [] of Endpoint
      prefix = prefix.strip('/')
      base_path = prefix.empty? ? "/" : "/#{prefix}"
      create_path = base_path == "/" ? "/create" : "#{base_path}/create"
      member_path = base_path == "/" ? "/{id}" : "#{base_path}/{id}"
      edit_path = base_path == "/" ? "/{id}/edit" : "#{base_path}/{id}/edit"

      endpoints << Endpoint.new(base_path, "GET", [] of Param, Details.new(PathInfo.new(file_path, line)))
      endpoints << Endpoint.new(create_path, "GET", [] of Param, Details.new(PathInfo.new(file_path, line)))
      endpoints << Endpoint.new(base_path, "POST", [] of Param, Details.new(PathInfo.new(file_path, line)))
      endpoints << Endpoint.new(member_path, "GET", [Param.new("id", "", "path")], Details.new(PathInfo.new(file_path, line)))
      endpoints << Endpoint.new(edit_path, "GET", [Param.new("id", "", "path")], Details.new(PathInfo.new(file_path, line)))
      endpoints << Endpoint.new(member_path, "PUT", [Param.new("id", "", "path")], Details.new(PathInfo.new(file_path, line)))
      endpoints << Endpoint.new(member_path, "DELETE", [Param.new("id", "", "path")], Details.new(PathInfo.new(file_path, line)))

      endpoints
    end

    private def inside_group_body?(pos : Int32, groups : Array(RouteGroup)) : Bool
      groups.any? { |group| pos >= group.body_start && pos < group.body_end }
    end

    private def extract_inline_closure_body(content : String, pos : Int32, base_line : Int32) : Tuple(String?, Int32, Int32?)
      return {nil, pos, nil} unless pos < content.size

      scan_pos = skip_whitespace(content, pos)
      return {nil, pos, nil} unless scan_pos < content.size

      closure_regex = /\A(?:static\s+)?function\s*\([^)]*\)\s*(?:use\s*\([^)]*\)\s*)?(?::\s*[^{=]+)?\{/i
      match = content[scan_pos..].match(closure_regex)
      return {nil, pos, nil} unless match

      brace_pos = scan_pos + match[0].size - 1
      body_end = find_matching_php_close_brace(content, brace_pos)
      return {nil, pos, nil} unless body_end

      body_start_line = base_line + newline_count_before(content, brace_pos)
      {content[(brace_pos + 1)...body_end], body_end + 1, body_start_line}
    end

    private def skip_whitespace(content : String, pos : Int32) : Int32
      while pos < content.size && content[pos].ascii_whitespace?
        pos += 1
      end
      pos
    end

    private def newline_count_before(content : String, pos : Int32) : Int32
      return 0 if pos <= 0
      content[0...pos].count('\n')
    end

    private def normalize_route(route : String) : String
      normalized = route.gsub(/\[:(\w+)\]/) { ":#{$1}" }
      normalized = normalized.gsub(/:(\w+)/) { "{#{$1}}" }
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized = normalized.gsub(/\/+/, "/")
      normalized = normalized.chomp('/') if normalized.size > 1
      normalized
    end

    private def extract_path_params(route_path : String) : Array(Param)
      params = [] of Param
      route_path.scan(/(?:\[)?:(\w+)(?:\])?/).each do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def extract_methods_from_string(methods_str : String) : Array(String)
      return ALL_METHODS if methods_str == "*"
      methods = [] of String
      methods_str.split('|').each do |m|
        methods << m.strip.upcase
      end
      methods.empty? ? ["GET"] : methods
    end

    private def attach_route_callees(endpoint : Endpoint,
                                     body : String?,
                                     file_path : String,
                                     start_line : Int32?,
                                     handler : Tuple(String, String)? = nil)
      if body && start_line
        callees = Noir::PhpCalleeExtractor.callees_for_body(body, file_path, start_line)
        attach_php_callees(endpoint, callees)
        return
      end

      # Explicit ThinkPHP routes name their handler as a string —
      # `'v1.user.User/save_info'` (dotted controller + `/method`) — or an
      # `[Controller::class, 'method']` pair, never an inline closure. Resolve
      # the controller file under `app/<app>/controller/` so these routes
      # surface callees / ai-context instead of staying blind.
      return unless handler

      resolved = resolve_handler_method_body(handler[0], handler[1], file_path)
      return unless resolved

      method_body, controller_path, method_line = resolved
      callees = Noir::PhpCalleeExtractor.callees_for_body(method_body, controller_path, method_line)
      attach_php_callees(endpoint, callees)
    end

    # Parse the controller reference following a route's pattern argument.
    # Handles `'v1.user.User/save_info'`, `'v1.user.User@save_info'`, and
    # `[\app\...\User::class, 'save_info']`. Returns {controller_ref, method}.
    private def extract_route_handler(content : String, pos : Int32) : Tuple(String, String)?
      scan_pos = skip_whitespace(content, pos)
      return unless scan_pos < content.size

      rest = content[scan_pos..]

      if m = rest.match(/\A['"]([^'"\/@]+)[\/@]([A-Za-z_]\w*)['"]/)
        return {m[1], m[2]}
      end

      if m = rest.match(/\A\[\s*([A-Za-z_\\][\w\\]*)::class\s*,\s*['"]([A-Za-z_]\w*)['"]/)
        return {m[1], m[2]}
      end

      nil
    end

    private def resolve_handler_method_body(controller_ref : String,
                                            method_name : String,
                                            route_file_path : String) : Tuple(String, String, Int32)?
      controller_path = resolve_controller_path(controller_ref, route_file_path)
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
      logger.debug "Error resolving ThinkPHP handler #{controller_ref}/#{method_name}: #{e}"
      nil
    end

    # Map a controller reference to a file under the owning app's
    # `controller/` directory. A route file lives at
    # `.../app/<app>/route/<file>.php`, so its sibling `controller/` holds
    # the controllers. Dotted refs (`v1.user.User`) and namespaced refs
    # (`app\adminapi\controller\v1\user\User`) both collapse to
    # `controller/v1/user/User.php`.
    private def resolve_controller_path(controller_ref : String, route_file_path : String) : String?
      segments = route_file_path.split('/')
      route_idx = segments.rindex("route")
      return unless route_idx && route_idx >= 1

      app_dir = segments[0...route_idx].join('/')
      return if app_dir.empty?

      rel = controller_ref.gsub('\\', '/')
      if marker = rel.index("controller/")
        rel = rel[(marker + "controller/".size)..]
      elsif !rel.includes?('/')
        rel = rel.gsub('.', '/')
      end
      rel = rel.strip('/')
      return if rel.empty? || rel.includes?("..")

      File.join(app_dir, "controller", "#{rel}.php")
    end

    # Implicit Controller Auto-Routing
    private def analyze_controller(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint

      info = extract_controller_info(path, content)
      return endpoints unless info
      module_slug, controller_slug_slash, controller_slug_dot = info

      offset = 0
      content.scan(/(?:^|[\s;{}])(?:public\s+)?function\s+([A-Za-z_]\w*)\s*\(([^)]*)\)(?:\s*:\s*[^{]+)?\s*\{/) do |match|
        action_name = match[1]
        param_sig = match[2]
        full_match = match[0]

        next if action_name.starts_with?("_")

        method_start = content.index(full_match, offset)
        next unless method_start
        offset = method_start + full_match.size

        action_slug = camel_to_snake(action_name)

        # Build route paths for both slash and dot patterns
        route_paths = [] of String
        if module_slug.empty?
          route_paths << "/#{controller_slug_slash}/#{action_slug}"
          route_paths << "/#{controller_slug_dot}/#{action_slug}" if controller_slug_slash != controller_slug_dot
        else
          route_paths << "/#{module_slug}/#{controller_slug_slash}/#{action_slug}"
          route_paths << "/#{module_slug}/#{controller_slug_dot}/#{action_slug}" if controller_slug_slash != controller_slug_dot
        end

        params = extract_action_signature_params(param_sig)

        method_body_info = extract_php_method_body_after(content, method_start)
        method_body = method_body_info ? method_body_info[0] : ""
        body_params = extract_request_params(method_body)

        seen = Set(String).new(params.map(&.name))
        body_params.each do |param|
          next if seen.includes?(param.name)
          params << param
          seen.add(param.name)
        end

        params = dedup_params(params)
        details = Details.new(PathInfo.new(path))
        methods = infer_methods_from_body(method_body)

        route_paths.uniq.each do |route_path|
          methods.each do |method|
            endpoint = Endpoint.new(route_path, method, params.dup, details.dup)
            attach_action_callees(endpoint, method_body_info, path) if include_callee
            endpoints << endpoint
          end
        end

        # Fallback root route for index action
        if action_slug == "index"
          fallback_paths = [] of String
          if module_slug.empty?
            fallback_paths << "/#{controller_slug_slash}"
            fallback_paths << "/#{controller_slug_dot}" if controller_slug_slash != controller_slug_dot
          else
            fallback_paths << "/#{module_slug}/#{controller_slug_slash}"
            fallback_paths << "/#{module_slug}/#{controller_slug_dot}" if controller_slug_slash != controller_slug_dot
          end

          fallback_paths.uniq.each do |fallback_path|
            methods.each do |method|
              endpoint = Endpoint.new(fallback_path, method, params.dup, details.dup)
              attach_action_callees(endpoint, method_body_info, path) if include_callee
              endpoints << endpoint
            end
          end
        end
      end

      endpoints
    end

    private def extract_controller_info(path : String, content : String) : Tuple(String, String, String)?
      basename = File.basename(path, ".php")
      return unless basename.ends_with?("Controller") || content.includes?("class ")

      class_name = basename
      if match = content.match(/class\s+(\w+)/)
        class_name = match[1]
      end

      controller_name = class_name
      if controller_name.ends_with?("Controller")
        controller_name = controller_name[0...-"Controller".size]
      end

      controller_slug = camel_to_snake(controller_name)

      segments = path.split('/')
      controller_idx = segments.index("controller")
      module_slug = ""
      subdirs = [] of String

      if controller_idx && controller_idx > 0
        parent = segments[controller_idx - 1]
        if parent != "app" && parent != "application"
          module_slug = camel_to_snake(parent)
        end

        # Capture nested subdirectories under controller/
        (controller_idx + 1...segments.size - 1).each do |i|
          subdirs << camel_to_snake(segments[i])
        end
      end

      controller_slug_slash = if subdirs.empty?
                                controller_slug
                              else
                                subdirs.join('/') + "/" + controller_slug
                              end

      controller_slug_dot = if subdirs.empty?
                              controller_slug
                            else
                              subdirs.join('.') + "." + controller_slug
                            end

      {module_slug, controller_slug_slash, controller_slug_dot}
    end

    private def extract_action_signature_params(signature : String) : Array(Param)
      params = [] of Param
      return params if signature.strip.empty?

      signature.split(',').each do |part|
        cleaned = part.strip
        next if cleaned.empty?
        next if cleaned.includes?("Request ") || cleaned.includes?("\\Request ")
        if match = cleaned.match(/\$(\w+)/)
          next if match[1].downcase == "request"
          params << Param.new(match[1], "", "query")
        end
      end
      params
    end

    private def extract_request_params(context : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      # 1. input('name') or input('get.name')
      context.scan(/input\s*\(\s*['"](?:get\.|post\.|param\.)?([^'"\/]+)[^'"]*['"]/) do |match|
        name = match[1]
        name = name[1..] if name.starts_with?('?')
        next if seen.includes?(name)
        param_type = if match[0].includes?("post.")
                       "form"
                     elsif match[0].includes?("get.")
                       "query"
                     elsif context.includes?("post.") || context.includes?("->post(") || context.includes?("request()->post")
                       "form"
                     else
                       "query"
                     end
        params << Param.new(name, "", param_type)
        seen.add(name)
      end

      # 2. $request->param("name"), $this->request->param("name"), request()->param("name"), Request::param("name")
      context.scan(/(?:\$this->request|\$request|request\(\)|(?:\\?think\\facade\\)?Request)(?:->|::)(param|get|post|put|delete|patch|header|cookie)\s*\(\s*['"]([^'"]+)['"]/i) do |match|
        method_name = match[1].downcase
        name = match[2]
        next if seen.includes?(name)

        param_type = case method_name
                     when "post", "put", "delete", "patch"
                       "form"
                     when "header"
                       "header"
                     when "cookie"
                       "cookie"
                     else
                       "query"
                     end

        params << Param.new(name, "", param_type)
        seen.add(name)
      end

      # 3. $_GET['name'], $_POST["name"], $_REQUEST['name'], $_COOKIE['name']
      context.scan(/\$_(GET|POST|REQUEST|COOKIE)\s*\[\s*['"]([^'"]+)['"]\s*\]/i) do |match|
        global_type = match[1].upcase
        name = match[2]
        next if seen.includes?(name)

        param_type = case global_type
                     when "POST"
                       "form"
                     when "COOKIE"
                       "cookie"
                     else
                       "query"
                     end

        params << Param.new(name, "", param_type)
        seen.add(name)
      end

      # 4. $_SERVER['HTTP_HEADER_NAME']
      context.scan(/\$_SERVER\s*\[\s*['"]HTTP_([^'"]+)['"]\s*\]/i) do |match|
        raw_header = match[1]
        header_name = raw_header.split('_').map(&.capitalize).join('-')
        next if seen.includes?(header_name)

        params << Param.new(header_name, "", "header")
        seen.add(header_name)
      end

      # 5. $request->only(['id', 'name']), Request::only(['id', 'name'])
      context.scan(/(?:\$this->request|\$request|request\(\)|(?:\\?think\\facade\\)?Request)(?:->|::)only\s*\(\s*\[([\s\S]+?)\]\s*\)/i) do |match|
        array_content = match[1]
        array_content.scan(/['"]([^'"]+)['"]/).each do |m|
          name = m[1]
          next if seen.includes?(name)
          param_type = context.includes?("post.") || context.includes?("->post(") || context.includes?("request()->post") || context.includes?("$_POST") || context.includes?("postMore") ? "form" : "query"
          params << Param.new(name, "", param_type)
          seen.add(name)
        end
      end

      # 6. $this->request->getMore([['page', 1], ['limit', 20]]) or Util::getMore([...]) or Request::postMore([...])
      context.scan(/(?:\$this->request|\$request|request\(\)|(?:\\?think\\facade\\)?Request|Util|Helper)(?:->|::)(getMore|postMore)\s*\(\s*\[([\s\S]+?)\]\s*\)/i) do |match|
        method_name = match[1].downcase
        array_content = match[2]
        param_type = method_name.includes?("post") ? "form" : "query"

        array_content.scan(/\[\s*['"]([^'"]+)['"]/).each do |m|
          name = m[1]
          next if seen.includes?(name)
          params << Param.new(name, "", param_type)
          seen.add(name)
        end
      end

      params
    end

    private def infer_methods_from_body(context : String) : Array(String)
      touches_post = context.includes?("->post(") ||
                     context.includes?("post.") ||
                     context.includes?("request()->post") ||
                     context.includes?("$_POST") ||
                     context.includes?("isPost")
      touches_post ? ["GET", "POST"] : ["GET"]
    end

    private def attach_action_callees(endpoint : Endpoint, method_body : Tuple(String, Int32)?, path : String)
      return unless method_body
      body, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def dedup_params(params : Array(Param)) : Array(Param)
      seen = Set(String).new
      params.select do |param|
        key = "#{param.param_type}\0#{param.name}"
        if seen.includes?(key)
          false
        else
          seen.add(key)
          true
        end
      end
    end

    private def analyze_annotation_routes(path : String, content : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Matches both #[Route("pattern", "method")] and /** @Route("pattern", "method") */
      annotation_regex = /(?:#\[\s*\\?Route|@Route)\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*['"]([^'"]+)['"])?/mi

      offset = 0
      loop do
        route_match = content.match(annotation_regex, offset)
        break unless route_match

        pattern = route_match[1]
        normalized_path = normalize_route(pattern)
        route_line = php_line_number_for_index(content, route_match.begin(0))

        methods = ["GET"]
        if method_str = route_match[2]?
          methods = extract_methods_from_string(method_str)
        end

        match_start = route_match.begin(0)
        method_body_info = extract_php_method_body_after(content, match_start)
        method_body = method_body_info ? method_body_info[0] : ""

        path_params = extract_path_params(pattern)
        body_params = extract_request_params(method_body)

        seen = Set(String).new(path_params.map(&.name))
        body_params.each do |param|
          next if seen.includes?(param.name)
          path_params << param
          seen.add(param.name)
        end

        params = dedup_params(path_params)
        details = Details.new(PathInfo.new(path, route_line))

        if route_match[2]?.nil?
          methods = infer_methods_from_body(method_body)
        end

        methods.each do |method|
          endpoint = Endpoint.new(normalized_path, method, params.dup, details.dup)
          attach_action_callees(endpoint, method_body_info, path) if include_callee
          endpoints << endpoint
        end

        offset = route_match.end(0)
      end

      endpoints
    end

    private def camel_to_snake(name : String) : String
      return "" if name.empty?
      result = String.build do |io|
        name.each_char_with_index do |char, i|
          if char.ascii_uppercase? && i > 0
            io << '_'
          end
          io << char.downcase
        end
      end
      result
    end
  end
end
