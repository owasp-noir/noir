require "../../engines/python_engine"

module Analyzer::Python
  class Starlette < PythonEngine
    # Route('/path', handler, methods=[...]) — captures path, and the tail
    # after the path literal so we can inspect methods= and the handler
    # reference. The tail stops at the closing paren on the same line to
    # keep the match cheap; multi-line Route() calls are still covered for
    # the common (path, handler, methods) shape.
    ROUTE_REGEX = /\b(WebSocketRoute|Route)\s*\(\s*[rf]?['"]([^'"]*)['"]([^)]*)/
    # Mount('/prefix', routes=[...]) — only the prefix literal is needed;
    # the routes list is scanned via the ongoing line loop while the mount
    # is on the paren stack.
    MOUNT_REGEX = /Mount\s*\(\s*[rf]?['"]([^'"]*)['"]/
    # Path param in a route pattern: {name} or {name:type}. Starlette uses
    # the :type suffix as a converter hint (int, str, float, uuid, path);
    # it is stripped before the param is exposed as a path param.
    PATH_PARAM_REGEX       = /\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[a-zA-Z_][a-zA-Z0-9_]*)?\}/
    TYPED_PATH_PARAM_REGEX = /\{([a-zA-Z_][a-zA-Z0-9_]*):[a-zA-Z_][a-zA-Z0-9_]*\}/

    # Hoisted out of the analyze loops: an interpolated regex literal
    # recompiles (PCRE2 JIT) on every evaluation, and these interpolate
    # only constants. The `.to_s` expansion is byte-identical to the
    # previous inline form, so matching behaviour is unchanged.
    ADD_ROUTE_RE        = /(#{DOT_NATION})\.add_(websocket_)?route\s*\((.*)\)/m
    CLASS_METHOD_DEF_RE = /^\s*(?:async\s+)?def\s+(get|post|put|patch|delete|head|options)\s*\(([^)]*)\)/

    # Request-access matchers interpolate a discovered request-var name
    # (`request`, `self.request`, ...) so they can't be class constants,
    # but a handler set only uses a handful of distinct names — memoize
    # the compiled set per name instead of rebuilding it on every line
    # of every handler body.
    private record AwaitBodyRegexes,
      json_await : Regex,
      form_await : Regex,
      json_assign : Regex,
      form_assign : Regex

    @await_body_regex_cache = Hash(::String, AwaitBodyRegexes).new
    @attr_regex_cache = Hash(Tuple(::String, ::String), Tuple(Regex, Regex)).new
    @body_var_regex_cache = Hash(::String, Tuple(Regex, Regex)).new
    @keyword_expr_regex_cache = Hash(::String, Regex).new

    private def await_body_regexes(request_name : ::String) : AwaitBodyRegexes
      @await_body_regex_cache[request_name] ||= begin
        rp = Regex.escape(request_name)
        AwaitBodyRegexes.new(
          json_await: /await\s+#{rp}\.json\s*\(/,
          form_await: /await\s+#{rp}\.form\s*\(/,
          json_assign: /([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+#{rp}\.json\s*\(/,
          form_assign: /([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+#{rp}\.form\s*\(/,
        )
      end
    end

    def analyze
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)

          source = read_file_content(path)
          next unless source.includes?("starlette")

          analyze_file(path, source, current_base_path)
        end
      end

      Fiber.yield
      result
    end

    private def analyze_file(path : ::String, source : ::String, definition_base_path : ::String)
      lines = source.split("\n")
      function_index = build_function_index(lines)
      class_index = build_class_index(lines)
      import_modules = find_imported_modules(definition_base_path, path, source)
      handler_cache = {} of ::String => Tuple(Array(Param), Array(Callee))
      external_handler_cache = {} of ::String => Tuple(Array(Param), Array(Callee))
      class_handler_cache = {} of ::String => Hash(::String, Tuple(Array(Param), Array(Callee)))
      websocket_class_handler_cache = {} of ::String => Tuple(Array(Param), Array(Callee))
      app_prefixes = build_app_prefixes(lines)
      mounted_route_list_prefixes = build_mounted_route_list_prefixes(lines, app_prefixes)
      mounted_route_list_ranges = build_mounted_route_list_ranges(lines, mounted_route_list_prefixes)
      # Stack of active Mount prefixes. Each entry stores the paren depth
      # at which the Mount was opened; when the running depth drops below
      # that value the mount has closed and its prefix must be popped.
      mount_stack = [] of Tuple(::String, Int32)
      paren_depth = 0

      lines.each_with_index do |line, line_index|
        # Route(...) and Mount(...) calls commonly span multiple
        # lines in real Starlette code. The line-level scan above
        # captures only the call header (`Route(`) on the first
        # line; the path string sits on a continuation line and
        # never matches the body regex. Coalesce continuation lines
        # into one logical string when the opening paren isn't
        # balanced on this line so the body capture sees the path.
        effective_line = if (line.includes?("Route") || line.includes?("Mount")) && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end
        # Lift `path=` keyword to the first positional slot so the
        # existing ROUTE_REGEX (which expects a string right after
        # `Route(`) matches `Route(path="/x", endpoint=h)`.
        effective_line = effective_line.gsub(/((?:WebSocketRoute|Route)\s*\()\s*path\s*=\s*([rf]?['"][^'"]*['"])/, "\\1\\2,")

        if effective_line.includes?(".add_route(") || effective_line.includes?(".add_websocket_route(")
          effective_line.scan(ADD_ROUTE_RE) do |programmatic_match|
            next if programmatic_match.size < 4
            receiver = normalize_receiver(programmatic_match[1])
            websocket_route = !(programmatic_match[2]?).to_s.empty?
            args = split_python_arguments(programmatic_match[3])
            route_path = extract_python_keyword_string(args, "path") || args[0]?.try { |arg| extract_python_string(arg) }
            next unless route_path

            handler_expr = extract_python_keyword_expression(args, "endpoint") || args[1]?.try(&.strip)
            next unless handler_expr
            handler_ref = clean_reference(handler_expr)
            next if handler_ref.empty?
            handler_name = handler_ref.split(".").last

            methods = websocket_route ? ["GET"] : extract_programmatic_methods(args)
            methods << "GET" if methods.empty?
            route_prefixes = app_prefixes[receiver]? || [""]

            route_prefixes.each do |prefix|
              full_url = normalize_route_url(prefix, route_path)
              if websocket_route
                handler_params = [] of Param
                handler_callees = [] of Callee
                if class_index.has_key?(handler_name)
                  handler_params, handler_callees = websocket_class_handler_context_for(lines, class_index, handler_name, path, websocket_class_handler_cache,
                    definition_base_path: definition_base_path, source: source)
                else
                  handler_params, handler_callees = handler_context_for_reference(handler_ref, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
                    definition_base_path: definition_base_path, source: source)
                end

                params = extract_path_params(route_path)
                handler_params.each do |p|
                  next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                  params << p
                end
                endpoint = Endpoint.new(full_url, "GET", params, Details.new(PathInfo.new(path, line_index + 1)))
                endpoint.protocol = "ws"
                handler_callees.each { |c| endpoint.push_callee(c) }
                result << endpoint
                next
              end

              if class_index.has_key?(handler_name)
                class_contexts = class_handler_contexts(lines, class_index, handler_name, path, class_handler_cache,
                  definition_base_path: definition_base_path, source: source)
                emit_methods = methods.empty? ? class_contexts.keys : methods
                emit_methods = ["GET"] if emit_methods.empty?

                emit_methods.uniq.each do |method|
                  params = extract_path_params(route_path)
                  handler_callees = [] of Callee
                  if class_context = class_contexts[method]?
                    handler_params, handler_callees = class_context
                    handler_params.each do |p|
                      next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                      params << p
                    end
                  end

                  endpoint = Endpoint.new(full_url, method, params, Details.new(PathInfo.new(path, line_index + 1)))
                  handler_callees.each { |c| endpoint.push_callee(c) }
                  result << endpoint
                end
              else
                handler_params, handler_callees = handler_context_for_reference(handler_ref, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
                  definition_base_path: definition_base_path, source: source)
                methods.uniq.each do |method|
                  params = extract_path_params(route_path)
                  handler_params.each do |p|
                    next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                    params << p
                  end

                  endpoint = Endpoint.new(full_url, method, params, Details.new(PathInfo.new(path, line_index + 1)))
                  handler_callees.each { |c| endpoint.push_callee(c) }
                  result << endpoint
                end
              end
            end
          end
        end

        if static_path = parse_staticfiles_mount_path(effective_line)
          route_prefixes = compose_route_prefixes(line_index, mounted_route_list_ranges, mount_stack)
          route_prefixes.each do |prefix|
            result << Endpoint.new(static_route_path(normalize_route_url(prefix, static_path)), "GET", Details.new(PathInfo.new(path, line_index + 1)))
          end
        end

        effective_line.scan(MOUNT_REGEX) do |match|
          next if match.size < 2
          mount_stack << {match[1], paren_depth + 1}
        end

        effective_line.scan(ROUTE_REGEX) do |match|
          next if match.size < 3
          route_kind = match[1]
          route_path = match[2]
          tail = match[3]
          websocket_route = route_kind == "WebSocketRoute"

          methods = [] of ::String
          methods_match = tail.match(/methods\s*=\s*\[([^\]]*)\]/)
          if methods_match
            methods_match[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
              methods << m[1].upcase
            end
          end
          explicit_methods = !methods.empty?

          path_params = extract_path_params(route_path)
          route_prefixes = compose_route_prefixes(line_index, mounted_route_list_ranges, mount_stack)

          handler_params = [] of Param
          handler_callees = [] of Callee
          handler_name = nil
          handler_ref = nil
          if endpoint_keyword_match = tail.match(/endpoint\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)/)
            handler_ref = endpoint_keyword_match[1]
            handler_name = handler_ref.split(".").last
          elsif positional_match = tail.match(/,\s*([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)/)
            handler_ref = positional_match[1]
            handler_name = handler_ref.split(".").last
          end

          if websocket_route
            if handler_name
              if class_index.has_key?(handler_name)
                handler_params, handler_callees = websocket_class_handler_context_for(lines, class_index, handler_name, path, websocket_class_handler_cache,
                  definition_base_path: definition_base_path, source: source)
              else
                handler_params, handler_callees = handler_context_for_reference(handler_ref || handler_name, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
                  definition_base_path: definition_base_path, source: source)
              end
            end

            route_prefixes.each do |prefix|
              full_url = normalize_route_url(prefix, route_path)
              params = [] of Param
              path_params.each { |p| params << p }
              handler_params.each do |p|
                next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                params << p
              end

              endpoint = Endpoint.new(full_url, "GET", params, Details.new(PathInfo.new(path, line_index + 1)))
              endpoint.protocol = "ws"
              handler_callees.each { |c| endpoint.push_callee(c) }
              result << endpoint
            end
            next
          end

          if handler_name && class_index.has_key?(handler_name)
            class_contexts = class_handler_contexts(lines, class_index, handler_name, path, class_handler_cache,
              definition_base_path: definition_base_path, source: source)
            class_methods = explicit_methods ? methods : class_contexts.keys
            class_methods = ["GET"] if class_methods.empty?

            route_prefixes.each do |prefix|
              full_url = normalize_route_url(prefix, route_path)
              class_methods.uniq.each do |method|
                params = [] of Param
                path_params.each { |p| params << p }

                handler_params = [] of Param
                handler_callees = [] of Callee
                if class_context = class_contexts[method]?
                  handler_params, handler_callees = class_context
                end
                handler_params.each do |p|
                  next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                  params << p
                end

                details = Details.new(PathInfo.new(path, line_index + 1))
                endpoint = Endpoint.new(full_url, method, params, details)
                handler_callees.each { |c| endpoint.push_callee(c) }
                result << endpoint
              end
            end
            next
          end

          methods << "GET" if methods.empty?
          if handler_ref || handler_name
            handler_params, handler_callees = handler_context_for_reference(handler_ref || handler_name.to_s, lines, function_index, path, import_modules, handler_cache, external_handler_cache,
              definition_base_path: definition_base_path, source: source)
          end

          route_prefixes.each do |prefix|
            full_url = normalize_route_url(prefix, route_path)
            methods.uniq.each do |method|
              params = [] of Param
              path_params.each { |p| params << p }
              handler_params.each do |p|
                next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
                params << p
              end

              details = Details.new(PathInfo.new(path, line_index + 1))
              endpoint = Endpoint.new(full_url, method, params, details)
              handler_callees.each { |c| endpoint.push_callee(c) }
              result << endpoint
            end
          end
        end

        paren_depth += line.count('(') - line.count(')')
        paren_depth = 0 if paren_depth < 0
        while !mount_stack.empty? && mount_stack.last[1] > paren_depth
          mount_stack.pop
        end
      end
    end

    private def normalize_route_url(prefix : ::String, route_path : ::String) : ::String
      full_url = "#{prefix}#{route_path}"
      full_url = "/#{full_url}".gsub(/\/+/, "/")
      full_url.gsub(TYPED_PATH_PARAM_REGEX) { |_| "{#{$~[1]}}" }
    end

    private def parse_staticfiles_mount_path(line : ::String) : ::String?
      return unless line.includes?("Mount") && line.includes?("StaticFiles")

      if match = line.match(/Mount\s*\(\s*[rf]?['"]([^'"]*)['"]/m)
        return match[1]
      end

      nil
    end

    private def static_route_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
    end

    private def build_mounted_route_list_prefixes(lines : Array(::String),
                                                  app_prefixes : Hash(::String, Array(::String))) : Hash(::String, Array(::String))
      prefixes = Hash(::String, Array(::String)).new do |hash, key|
        hash[key] = [] of ::String
      end
      app_route_lists = build_app_route_lists(lines)
      route_list_ranges = build_route_list_ranges(lines)
      mount_edges = [] of Tuple(::String?, ::String, ::String)

      app_route_lists.each do |app_name, route_lists|
        route_prefixes = app_prefixes[app_name]? || [""]
        route_lists.each do |route_list|
          route_prefixes.each do |prefix|
            add_route_list_prefix(prefixes, route_list, prefix)
          end
        end
      end

      lines.each_with_index do |line, line_index|
        next unless line.includes?("Mount") && (line.includes?("routes") || line.includes?("app"))

        effective_line = if line.includes?("Mount") && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end
        parent_route_list = route_list_parent_for_line(line_index, route_list_ranges)

        effective_line.scan(/Mount\s*\(\s*[rf]?['"]([^'"]*)['"][^)]*\broutes\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
          next if match.size < 3
          mount_edges << {parent_route_list, match[2], match[1]}
        end

        effective_line.scan(/Mount\s*\(\s*[rf]?['"]([^'"]*)['"][^)]*\bapp\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
          next if match.size < 3
          mount_prefix = match[1]
          app_name = match[2]
          route_lists = app_route_lists[app_name]?
          next unless route_lists

          route_lists.each do |route_list|
            mount_edges << {parent_route_list, route_list, mount_prefix}
          end
        end
      end

      mount_edges.each do |parent_route_list, route_list, mount_prefix|
        next if parent_route_list
        add_route_list_prefix(prefixes, route_list, mount_prefix)
      end

      changed = true
      while changed
        changed = false
        mount_edges.each do |parent_route_list, route_list, mount_prefix|
          next unless parent_route_list

          parent_prefixes = prefixes[parent_route_list]?
          next unless parent_prefixes

          parent_prefixes.each do |parent_prefix|
            composed_prefix = normalize_route_prefix(parent_prefix, mount_prefix)
            next if prefixes[route_list].includes?(composed_prefix)

            prefixes[route_list] << composed_prefix
            changed = true
          end
        end
      end

      prefixes
    end

    private def add_route_list_prefix(prefixes : Hash(::String, Array(::String)), route_list : ::String, prefix : ::String)
      normalized = prefix.empty? ? "" : normalize_route_prefix("", prefix)
      prefixes[route_list] << normalized unless prefixes[route_list].includes?(normalized)
    end

    private def normalize_route_prefix(parent_prefix : ::String, child_prefix : ::String) : ::String
      full_prefix = "#{parent_prefix}#{child_prefix}"
      full_prefix = "/#{full_prefix}".gsub(/\/+/, "/")
      full_prefix == "/" ? "" : full_prefix
    end

    private def route_list_parent_for_line(line_index : Int32, route_list_ranges : Hash(::String, Tuple(Int32, Int32))) : ::String?
      route_list_ranges.each do |route_list, range|
        start_line, end_line = range
        return route_list if line_index >= start_line && line_index <= end_line
      end

      nil
    end

    private def build_route_list_ranges(lines : Array(::String)) : Hash(::String, Tuple(Int32, Int32))
      ranges = Hash(::String, Tuple(Int32, Int32)).new

      lines.each_with_index do |line, line_index|
        assign_match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)(?:\s*:[^=]+)?\s*=\s*\[/)
        next unless assign_match

        end_line = line_index
        bracket_depth = 0
        index = line_index
        while index < lines.size
          bracket_depth += lines[index].count('[') - lines[index].count(']')
          end_line = index
          break if bracket_depth <= 0
          index += 1
        end

        ranges[assign_match[1]] = {line_index, end_line}
      end

      ranges
    end

    private def build_app_prefixes(lines : Array(::String)) : Hash(::String, Array(::String))
      prefixes = Hash(::String, Array(::String)).new do |hash, key|
        hash[key] = [] of ::String
      end
      mounts = [] of Tuple(::String, ::String)

      lines.each_with_index do |line, line_index|
        if app_match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:Starlette|Router)\s*\(/)
          prefixes[app_match[1]] << "" unless prefixes[app_match[1]].includes?("")
        end

        next unless line.includes?("Mount") && line.includes?("app")

        effective_line = if line.includes?("Mount") && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end

        effective_line.scan(/Mount\s*\(\s*[rf]?['"]([^'"]*)['"][^)]*\bapp\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
          next if match.size < 3
          mount_prefix = match[1]
          app_name = match[2]
          mounts << {mount_prefix, app_name}
          prefixes[app_name] ||= [] of ::String
        end
      end

      mounted_apps = Set(::String).new
      mounts.each { |_, app_name| mounted_apps << app_name }
      mounted_apps.each do |app_name|
        prefixes[app_name].try(&.delete(""))
      end

      mounts.each do |mount_prefix, app_name|
        prefixes[app_name] << mount_prefix unless prefixes[app_name].includes?(mount_prefix)
      end

      prefixes
    end

    private def build_app_route_lists(lines : Array(::String)) : Hash(::String, Array(::String))
      app_route_lists = Hash(::String, Array(::String)).new do |hash, key|
        hash[key] = [] of ::String
      end

      lines.each_with_index do |line, line_index|
        next unless line.includes?("Starlette") || line.includes?("Router")

        effective_line = if python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end

        effective_line.scan(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:Starlette|Router)\s*\([^)]*\broutes\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/m) do |match|
          next if match.size < 3
          app_route_lists[match[1]] << match[2]
        end
      end

      app_route_lists
    end

    private def build_mounted_route_list_ranges(lines : Array(::String),
                                                mounted_route_list_prefixes : Hash(::String, Array(::String))) : Array(Tuple(Int32, Int32, Array(::String)))
      ranges = [] of Tuple(Int32, Int32, Array(::String))
      return ranges if mounted_route_list_prefixes.empty?

      lines.each_with_index do |line, line_index|
        assign_match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)(?:\s*:[^=]+)?\s*=\s*\[/)
        next unless assign_match

        route_list_name = assign_match[1]
        prefixes = mounted_route_list_prefixes[route_list_name]?
        next unless prefixes

        end_line = line_index
        bracket_depth = 0
        index = line_index
        while index < lines.size
          bracket_depth += lines[index].count('[') - lines[index].count(']')
          end_line = index
          break if bracket_depth <= 0
          index += 1
        end

        ranges << {line_index, end_line, prefixes}
      end

      ranges
    end

    private def mounted_route_prefixes_for_line(line_index : Int32,
                                                mounted_route_list_ranges : Array(Tuple(Int32, Int32, Array(::String)))) : Array(::String)?
      mounted_route_list_ranges.each do |range|
        start_line, end_line, prefixes = range
        return prefixes if line_index >= start_line && line_index <= end_line
      end

      nil
    end

    # Compose the variable-assigned route-list prefix (outer mount,
    # resolved by name) with any active inline `Mount('/x', routes=[...])`
    # on the paren stack (inner mount). A route nested in an inline Mount
    # that itself lives inside a variable-assigned list (`routes = [...,
    # Mount('/admin', routes=[Route('/x')])]; app = Starlette(routes=routes)`)
    # matches the list range, which previously short-circuited and dropped
    # the inline mount's `/admin` prefix entirely.
    private def compose_route_prefixes(line_index : Int32,
                                       mounted_route_list_ranges : Array(Tuple(Int32, Int32, Array(::String))),
                                       mount_stack : Array(Tuple(::String, Int32))) : Array(::String)
      mount_prefix = mount_stack.map(&.[0]).join
      if range_prefixes = mounted_route_prefixes_for_line(line_index, mounted_route_list_ranges)
        range_prefixes.map { |prefix| "#{prefix}#{mount_prefix}" }
      else
        [mount_prefix]
      end
    end

    private def extract_path_params(route_path : ::String) : Array(Param)
      params = [] of Param
      route_path.scan(PATH_PARAM_REGEX) do |match|
        name = match[1]
        next if params.any? { |p| p.name == name }
        params << Param.new(name, "", "path")
      end
      params
    end

    private def extract_programmatic_methods(args : Array(::String)) : Array(::String)
      methods = [] of ::String
      expression = extract_python_keyword_expression(args, "methods")
      return methods unless expression

      expression.scan(/['"]([A-Za-z]+)['"]/) do |method_match|
        methods << method_match[1].upcase
      end
      methods.uniq
    end

    # Memoized per keyword — the keyword set is tiny (`path`, `endpoint`,
    # `methods`) but this runs per argument of every programmatic route.
    private def keyword_expression_regex(keyword : ::String) : Regex
      @keyword_expr_regex_cache[keyword] ||= /^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m
    end

    private def extract_python_keyword_expression(args : Array(::String), keyword : ::String) : ::String?
      keyword_re = keyword_expression_regex(keyword)
      args.each do |arg|
        keyword_match = arg.match(keyword_re)
        return keyword_match[1].strip if keyword_match
      end

      nil
    end

    private def extract_python_keyword_string(args : Array(::String), keyword : ::String) : ::String?
      if expression = extract_python_keyword_expression(args, keyword)
        return extract_python_string(expression)
      end

      nil
    end

    private def extract_python_string(expression : ::String) : ::String?
      string_match = expression.strip.match(/^[rf]?['"]([^'"]*)['"]/)
      string_match ? string_match[1] : nil
    end

    private def clean_reference(expression : ::String) : ::String
      reference = expression.strip
      reference = reference.split("#", 2)[0].strip
      reference = reference.split(",", 2)[0].strip
      reference.matches?(/^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$/) ? reference : ""
    end

    private def split_python_arguments(args : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      in_quote : Char? = nil
      escaped = false

      args.each_char do |ch|
        if in_quote
          current << ch
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          next
        end

        case ch
        when '\'', '"'
          in_quote = ch
          current << ch
        when '('
          paren_depth += 1
          current << ch
        when ')'
          paren_depth -= 1 if paren_depth > 0
          current << ch
        when '['
          bracket_depth += 1
          current << ch
        when ']'
          bracket_depth -= 1 if bracket_depth > 0
          current << ch
        when '{'
          brace_depth += 1
          current << ch
        when '}'
          brace_depth -= 1 if brace_depth > 0
          current << ch
        when ','
          if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
            parts << current.to_s
            current = String::Builder.new
          else
            current << ch
          end
        else
          current << ch
        end
      end

      parts << current.to_s
      parts
    end

    private def normalize_receiver(receiver : ::String) : ::String
      receiver.strip.split(".").last
    end

    private def build_function_index(lines : Array(::String)) : Hash(::String, Tuple(Int32, ::String))
      index = {} of ::String => Tuple(Int32, ::String)
      lines.each_with_index do |line, idx|
        def_match = line.match(/def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*([a-zA-Z_][a-zA-Z0-9_]*)/)
        next unless def_match
        name = def_match[1]
        next if index.has_key?(name)
        index[name] = {idx, def_match[2]}
      end
      index
    end

    private def build_class_index(lines : Array(::String)) : Hash(::String, Int32)
      index = {} of ::String => Int32
      lines.each_with_index do |line, idx|
        class_match = line.match(/^\s*class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[\(:]/)
        next unless class_match
        index[class_match[1]] ||= idx
      end
      index
    end

    private def class_handler_contexts(lines : Array(::String),
                                       class_index : Hash(::String, Int32),
                                       handler_name : ::String,
                                       path : ::String,
                                       cache : Hash(::String, Hash(::String, Tuple(Array(Param), Array(Callee)))),
                                       *,
                                       definition_base_path : ::String,
                                       source : ::String) : Hash(::String, Tuple(Array(Param), Array(Callee)))
      cached = cache[handler_name]?
      return cached if cached

      contexts = {} of ::String => Tuple(Array(Param), Array(Callee))
      class_line = class_index[handler_name]?
      unless class_line
        cache[handler_name] = contexts
        return contexts
      end

      class_indent = lines[class_line].size - lines[class_line].lstrip.size
      i = class_line + 1
      while i < lines.size
        line = lines[i]
        unless line.strip.empty?
          indent = line.size - line.lstrip.size
          break if indent <= class_indent

          if method_match = line.match(CLASS_METHOD_DEF_RE)
            method = method_match[1].upcase
            request_name = extract_request_arg_name(method_match[2])
            request_body_res = request_name ? await_body_regexes(request_name) : nil
            codeblock = parse_code_block(lines[i..])
            if codeblock
              params = [] of Param
              codeblock.split("\n").each do |cl|
                if request_name && request_body_res
                  collect_request_attr_params(cl, request_name, "path_params", "path", params)
                  collect_request_attr_params(cl, request_name, "query_params", "query", params)
                  collect_request_attr_params(cl, request_name, "headers", "header", params)
                  collect_request_attr_params(cl, request_name, "cookies", "cookie", params)

                  if cl.matches?(request_body_res.json_await)
                    add_unique(params, Param.new("body", "", "json"))
                  end
                  if cl.matches?(request_body_res.form_await)
                    add_unique(params, Param.new("body", "", "form"))
                  end
                end

                collect_request_attr_params(cl, "self.request", "path_params", "path", params)
                collect_request_attr_params(cl, "self.request", "query_params", "query", params)
                collect_request_attr_params(cl, "self.request", "headers", "header", params)
                collect_request_attr_params(cl, "self.request", "cookies", "cookie", params)

                if cl.matches?(/await\s+self\.request\.json\s*\(/)
                  add_unique(params, Param.new("body", "", "json"))
                end
                if cl.matches?(/await\s+self\.request\.form\s*\(/)
                  add_unique(params, Param.new("body", "", "form"))
                end
              end
              collect_request_body_params(codeblock, request_name, params) if request_name
              collect_request_body_params(codeblock, "self.request", params)

              callees = build_callees_from(codeblock, i, path,
                definition_base_path: definition_base_path, source: source)
              contexts[method] = {params, callees}
            end
          end
        end
        i += 1
      end

      cache[handler_name] = contexts
      contexts
    end

    private def websocket_class_handler_context_for(lines : Array(::String),
                                                    class_index : Hash(::String, Int32),
                                                    handler_name : ::String,
                                                    path : ::String,
                                                    cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                                    *,
                                                    definition_base_path : ::String,
                                                    source : ::String) : Tuple(Array(Param), Array(Callee))
      cached = cache[handler_name]?
      return cached if cached

      params = [] of Param
      callees = [] of Callee
      class_line = class_index[handler_name]?
      unless class_line
        cache[handler_name] = {params, callees}
        return cache[handler_name]
      end

      class_codeblock = parse_code_block(lines[class_line..])
      unless class_codeblock
        cache[handler_name] = {params, callees}
        return cache[handler_name]
      end

      class_codeblock.split("\n").each do |cl|
        if method_match = cl.match(/^\s*(?:async\s+)?def\s+(?:on_connect|on_receive|on_disconnect)\s*\(([^)]*)\)/)
          if request_name = extract_request_arg_name(method_match[1])
            collect_websocket_params(class_codeblock, request_name, params)
          end
        end
      end

      callees = build_callees_from(class_codeblock, class_line, path,
        definition_base_path: definition_base_path, source: source)
      cache[handler_name] = {params, callees}
      cache[handler_name]
    end

    private def extract_request_arg_name(args : ::String) : ::String?
      names = args.split(",").map do |arg|
        arg.split("=", 2)[0].split(":", 2)[0].strip
      end.reject(&.empty?)
      names.find { |name| name != "self" && name != "cls" }
    end

    private def handler_context_for(lines : Array(::String),
                                    function_index : Hash(::String, Tuple(Int32, ::String)),
                                    handler_name : ::String,
                                    path : ::String,
                                    cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                    *,
                                    definition_base_path : ::String,
                                    source : ::String) : Tuple(Array(Param), Array(Callee))
      cached = cache[handler_name]?
      return cached if cached

      params = [] of Param
      callees = [] of Callee

      entry = function_index[handler_name]?
      unless entry
        cache[handler_name] = {params, callees}
        return cache[handler_name]
      end
      idx, request_name = entry

      codeblock = parse_code_block(lines[idx..])
      if codeblock.nil?
        cache[handler_name] = {params, callees}
        return cache[handler_name]
      end

      request_body_res = await_body_regexes(request_name)
      codeblock.split("\n").each do |cl|
        collect_websocket_params(cl, request_name, params)

        if cl.matches?(request_body_res.json_await)
          add_unique(params, Param.new("body", "", "json"))
        end
        if cl.matches?(request_body_res.form_await)
          add_unique(params, Param.new("body", "", "form"))
        end
      end
      collect_request_body_params(codeblock, request_name, params)

      callees = build_callees_from(codeblock, idx, path,
        definition_base_path: definition_base_path, source: source)
      cache[handler_name] = {params, callees}
      cache[handler_name]
    end

    private def handler_context_for_reference(handler_ref : ::String,
                                              lines : Array(::String),
                                              function_index : Hash(::String, Tuple(Int32, ::String)),
                                              path : ::String,
                                              import_modules : Hash(::String, Tuple(::String, Int32)),
                                              cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                              external_cache : Hash(::String, Tuple(Array(Param), Array(Callee))),
                                              *,
                                              definition_base_path : ::String,
                                              source : ::String) : Tuple(Array(Param), Array(Callee))
      clean_ref = clean_reference(handler_ref)
      return {[] of Param, [] of Callee} if clean_ref.empty?

      unless clean_ref.includes?(".")
        return handler_context_for(lines, function_index, clean_ref, path, cache,
          definition_base_path: definition_base_path, source: source)
      end

      receiver, handler_name = clean_ref.split(".", 2)
      handler_path = ""
      if import_info = import_modules[receiver]?
        handler_path = import_info.first
      end
      handler_path = File.join(File.dirname(path), "#{receiver}.py") if handler_path.empty?
      return {[] of Param, [] of Callee} unless File.exists?(handler_path)

      cache_key = "#{handler_path}:#{handler_name}"
      cached = external_cache[cache_key]?
      return cached if cached

      handler_source = read_file_content(handler_path)
      handler_lines = handler_source.split("\n")
      handler_function_index = build_function_index(handler_lines)
      context = handler_context_for(handler_lines, handler_function_index, handler_name, handler_path, {} of ::String => Tuple(Array(Param), Array(Callee)),
        definition_base_path: definition_base_path, source: handler_source)
      external_cache[cache_key] = context
      context
    end

    private def collect_websocket_params(source : ::String, request_name : ::String, params : Array(Param))
      source.each_line do |line|
        collect_request_attr_params(line, request_name, "path_params", "path", params)
        collect_request_attr_params(line, request_name, "query_params", "query", params)
        collect_request_attr_params(line, request_name, "headers", "header", params)
        collect_request_attr_params(line, request_name, "cookies", "cookie", params)
      end
    end

    private def request_attr_regexes(request_name : ::String, attr : ::String) : Tuple(Regex, Regex)
      @attr_regex_cache[{request_name, attr}] ||= begin
        rp = Regex.escape(request_name)
        {/#{rp}\.#{attr}\[\s*[rf]?['"]([^'"]+)['"]\s*\]/,
         /#{rp}\.#{attr}\.get\(\s*[rf]?['"]([^'"]+)['"]/}
      end
    end

    private def collect_request_attr_params(line : ::String, request_name : ::String, attr : ::String, noir_type : ::String, params : Array(Param))
      # The attr substring is a necessary condition for either pattern,
      # so most lines skip the regex matches entirely.
      return unless line.includes?(attr)
      bracket_re, get_re = request_attr_regexes(request_name, attr)
      line.scan(bracket_re) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
      line.scan(get_re) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
    end

    private def body_var_regexes(var : ::String) : Tuple(Regex, Regex)
      @body_var_regex_cache[var] ||= begin
        v = Regex.escape(var)
        {/(?:^|[^a-zA-Z0-9_])#{v}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/,
         /(?:^|[^a-zA-Z0-9_])#{v}\.get\(\s*[rf]?['"]([^'"]+)['"]/}
      end
    end

    private def collect_request_body_params(codeblock : ::String, request_name : ::String, params : Array(Param))
      request_body_res = await_body_regexes(request_name)
      { {"json", request_body_res.json_assign}, {"form", request_body_res.form_assign} }.each do |noir_type, assign_re|
        body_vars = [] of ::String
        codeblock.scan(assign_re) do |m|
          body_vars << m[1]
        end

        body_vars.each do |var|
          bracket_re, get_re = body_var_regexes(var)
          codeblock.scan(bracket_re) do |m|
            add_unique(params, Param.new(m[1], "", noir_type))
          end
          codeblock.scan(get_re) do |m|
            add_unique(params, Param.new(m[1], "", noir_type))
          end
        end
      end
    end

    private def add_unique(params : Array(Param), param : Param)
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end
  end
end
