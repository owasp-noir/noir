require "../../engines/python_engine"

module Analyzer::Python
  class Litestar < PythonEngine
    # Decorator matching: @get("/path"), @post("/path"), etc. The tail
    # after the path literal is captured so extra kwargs (like methods=)
    # can be inspected for multi-method @route decorators.
    # `websocket(?:_listener|_stream)?` also matches Litestar's
    # `@websocket_listener("/ws")` and `@websocket_stream("/ws")`
    # decorators (the listener/stream class-based WS handlers), which
    # take a positional path just like `@websocket` — without the
    # variants every listener/stream endpoint was silently dropped.
    DECORATOR_REGEX = /@(get|post|put|patch|delete|head|options|route|websocket(?:_listener|_stream)?)\s*\(([^)]*)/
    # Path literal inside a decorator. Litestar accepts both a positional
    # path and an explicit `path=` keyword argument.
    DECORATOR_PATH_REGEX    = /^\s*[rf]?['"]([^'"]*)['"]/
    DECORATOR_PATH_KW_REGEX = /path\s*=\s*[rf]?['"]([^'"]*)['"]/
    HTTP_METHOD_KW_REGEX    = /http_method\s*=\s*(?:\[([^\]]*)\]|['"]([^'"]+)['"])/
    # Router(path="/prefix", route_handlers=[...])
    ROUTER_REGEX = /(#{PYTHON_VAR_NAME_REGEX})\s*=\s*Router\s*\(([^)]*)\)/m
    # Path param: {name} or {name:type}. Litestar uses the :type suffix
    # as a converter (int, str, uuid, path, float); strip it when
    # exposing the param.
    PATH_PARAM_REGEX       = /\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[a-zA-Z_][a-zA-Z0-9_]*)?\}/
    TYPED_PATH_PARAM_REGEX = /\{([a-zA-Z_][a-zA-Z0-9_]*):[a-zA-Z_][a-zA-Z0-9_]*\}/

    # Hoisted out of the per-line/per-param loops: an interpolated regex
    # literal recompiles (PCRE2 JIT) on every evaluation, and these
    # interpolate only constants or fixed sets. The `.to_s` expansion is
    # byte-identical to the previous inline form, so matching behaviour
    # is unchanged.
    DOTTED_HANDLER_RE   = /(#{PYTHON_VAR_NAME_REGEX})\.(#{PYTHON_VAR_NAME_REGEX})/
    CONTROLLER_CLASS_RE = /^\s*class\s+(#{PYTHON_VAR_NAME_REGEX})\s*\(([^)]*)\)/
    CLASS_HEAD_RE       = /^\s*class\s+(#{PYTHON_VAR_NAME_REGEX})\s*\(/

    # `classify_param` runs once per typed handler parameter and rebuilt
    # one PCRE2 pattern per primitive type on every call.
    PRIMITIVE_TYPE_PATTERNS = ["str", "int", "float", "bool", "bytes", "UUID", "date", "datetime"].map do |t|
      /\b#{t}\b/
    end

    # `collect_request_attr_params` runs twice per handler-body line per
    # attribute; the attribute set is fixed, so precompile the patterns.
    REQUEST_ATTR_PATTERNS = %w[query_params path_params headers cookies].to_h do |attr|
      {attr, {
        /request\.#{attr}\[\s*[rf]?['"]([^'"]+)['"]\s*\]/,
        /request\.#{attr}\.get\(\s*[rf]?['"]([^'"]+)['"]/,
      }}
    end

    def analyze
      python_files = get_files_by_extension(".py")
      external_handler_prefixes = Hash(::String, Hash(::String, ::String)).new do |hash, key|
        hash[key] = Hash(::String, ::String).new
      end

      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)

          source = read_file_content(path)
          next unless source.includes?("litestar")

          import_modules = find_imported_modules(current_base_path, path, source)
          collect_external_handler_prefixes(source, collect_router_prefixes(source), import_modules).each do |handler_path, handler_map|
            handler_map.each do |handler_name, prefix|
              external_handler_prefixes[handler_path][handler_name] = prefix
            end
          end
        end
      end

      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)

          source = read_file_content(path)
          next unless source.includes?("litestar")

          analyze_file(path, source, current_base_path, external_handler_prefixes[path]? || Hash(::String, ::String).new)
        end
      end

      Fiber.yield
      result
    end

    private def analyze_file(path : ::String,
                             source : ::String,
                             definition_base_path : ::String,
                             handler_prefix_overrides : Hash(::String, ::String))
      lines = source.split("\n")
      router_prefixes = collect_router_prefixes(source)
      handler_routers = collect_handler_to_router(source, router_prefixes)
      controller_prefixes = collect_controller_prefixes(lines)

      lines.each_with_index do |line, line_index|
        # Coalesce multi-line decorator calls so paths on
        # continuation lines (`@post(\n  "/items",\n  tags=...,\n)`)
        # still feed the same single-line regex below. `line_index`
        # remains the decorator line so handler discovery / code_paths
        # stay aligned with the source.
        effective_line = coalesce_litestar_decorator(lines, line_index, line)
        effective_line.scan(DECORATOR_REGEX) do |match|
          next if match.size < 3
          decorator = match[1].downcase
          body = match[2]

          path_match = body.match(DECORATOR_PATH_REGEX) || body.match(DECORATOR_PATH_KW_REGEX)
          next unless path_match
          route_path = path_match[1]

          methods = [] of ::String
          websocket_route = decorator.starts_with?("websocket")
          if decorator == "route"
            http_match = body.match(HTTP_METHOD_KW_REGEX)
            if http_match
              if list_content = http_match[1]?
                list_content.scan(/['"]([A-Za-z]+)['"]/) { |m| methods << m[1].upcase }
              elsif single_method = http_match[2]?
                methods << single_method.upcase
              end
            end
            methods << "GET" if methods.empty?
          elsif websocket_route
            methods << "GET"
          else
            methods << decorator.upcase
          end

          handler_name, handler_line = find_handler(lines, line_index)
          prefix = handler_name ? handler_prefix_overrides[handler_name]? || handler_routers[handler_name]? || "" : ""
          if hl = handler_line
            if controller_info = controller_for_handler(lines, hl, controller_prefixes)
              controller_name, controller_prefix = controller_info
              prefix = "#{handler_routers[controller_name]? || ""}#{controller_prefix}"
            end
          end

          full_path = "#{prefix}#{route_path}"
          full_path = "/#{full_path}" unless full_path.starts_with?("/")
          full_path = full_path.gsub(/\/+/, "/")
          full_path = full_path.gsub(TYPED_PATH_PARAM_REGEX) { |_| "{#{$~[1]}}" }

          path_params = extract_path_params(full_path)

          # Parse the handler body once and share between param and
          # callee extraction — both used to call `parse_code_block`
          # independently, costing 2 parses per handler.
          handler_body = if hl = handler_line
                           parse_code_block(lines[hl..])
                         end
          handler_params = handler_line ? extract_handler_params(lines, handler_line, full_path, handler_body) : [] of Param

          # Build once per handler — a decorator can emit multiple
          # endpoints when @route(http_method=[...]) lists several verbs.
          handler_callees = if handler_body && (hl = handler_line)
                              build_callees_from(
                                handler_body,
                                hl,
                                path,
                                definition_base_path: definition_base_path,
                                source: source
                              )
                            else
                              [] of Callee
                            end

          methods.uniq.each do |method|
            params = [] of Param
            path_params.each { |p| params << p }
            handler_params.each do |p|
              next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
              params << p
            end

            details = Details.new(PathInfo.new(path, line_index + 1))
            endpoint = Endpoint.new(full_path, method, params, details)
            endpoint.protocol = "ws" if websocket_route
            handler_callees.each { |c| endpoint.push_callee(c) }
            result << endpoint
          end
        end
      end
    end

    # Walk forward from the decorator line to locate the first function
    # definition. Returns {name, line_index} or {nil, nil}.
    private def find_handler(lines : Array(::String), decorator_index : Int32) : Tuple(::String?, Int32?)
      idx = decorator_index + 1
      while idx < lines.size
        def_match = lines[idx].match(/(?:async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/)
        return {def_match[1], idx} if def_match
        # Allow chained decorators on following lines
        stripped = lines[idx].lstrip
        if stripped.starts_with?("@") || stripped.empty?
          idx += 1
          next
        end
        break
      end
      {nil, nil}
    end

    # Collect Router(path="/prefix") assignments. The key is the router
    # variable name; the value is the prefix.
    private def collect_router_prefixes(source : ::String) : Hash(::String, ::String)
      prefixes = Hash(::String, ::String).new
      source.scan(ROUTER_REGEX) do |match|
        next if match.size < 3
        name = match[1]
        body = match[2]
        prefix_match = body.match(/path\s*=\s*[rf]?['"]([^'"]*)['"]/)
        prefix_match ||= body.match(/^\s*[rf]?['"]([^'"]*)['"]/)
        prefixes[name] = prefix_match ? prefix_match[1] : ""
      end
      prefixes
    end

    # Walk each Router(...) block and map handler-function names in
    # route_handlers to the router's prefix, so handler endpoints inherit
    # the prefix when the route is registered on a Router.
    private def collect_handler_to_router(source : ::String, router_prefixes : Hash(::String, ::String)) : Hash(::String, ::String)
      mapping = Hash(::String, ::String).new
      source.scan(ROUTER_REGEX) do |match|
        next if match.size < 3
        router_name = match[1]
        body = match[2]
        prefix = router_prefixes[router_name]? || ""
        handlers_match = body.match(/route_handlers\s*=\s*\[([^\]]*)\]/m)
        next unless handlers_match
        handlers_match[1].scan(/([a-zA-Z_][a-zA-Z0-9_]*)/) do |m|
          name = m[1]
          next if name == "route_handlers"
          mapping[name] = prefix unless mapping.has_key?(name)
        end
      end

      source.scan(/Router\s*\(([^)]*)\)/m) do |match|
        next if match.size < 2
        body = match[1]
        prefix_match = body.match(/path\s*=\s*[rf]?['"]([^'"]*)['"]/)
        prefix_match ||= body.match(/^\s*[rf]?['"]([^'"]*)['"]/)
        prefix = prefix_match ? prefix_match[1] : ""

        handlers_match = body.match(/route_handlers\s*=\s*\[([^\]]*)\]/m)
        next unless handlers_match
        handlers_match[1].scan(/([a-zA-Z_][a-zA-Z0-9_]*)/) do |m|
          name = m[1]
          next if name == "route_handlers"
          mapping[name] = prefix unless mapping.has_key?(name)
        end
      end

      mapping
    end

    private def collect_external_handler_prefixes(source : ::String,
                                                  router_prefixes : Hash(::String, ::String),
                                                  import_modules : Hash(::String, Tuple(::String, Int32))) : Hash(::String, Hash(::String, ::String))
      mapping = Hash(::String, Hash(::String, ::String)).new do |hash, key|
        hash[key] = Hash(::String, ::String).new
      end

      source.scan(ROUTER_REGEX) do |match|
        next if match.size < 3
        router_name = match[1]
        body = match[2]
        prefix = router_prefixes[router_name]? || ""
        map_external_route_handlers(body, prefix, import_modules, mapping)
      end

      source.scan(/Router\s*\(([^)]*)\)/m) do |match|
        next if match.size < 2
        body = match[1]
        prefix_match = body.match(/path\s*=\s*[rf]?['"]([^'"]*)['"]/)
        prefix_match ||= body.match(/^\s*[rf]?['"]([^'"]*)['"]/)
        prefix = prefix_match ? prefix_match[1] : ""
        map_external_route_handlers(body, prefix, import_modules, mapping)
      end

      source.scan(/Litestar\s*\(([^)]*)\)/m) do |match|
        next if match.size < 2
        map_external_route_handlers(match[1], "", import_modules, mapping)
      end

      mapping
    end

    private def map_external_route_handlers(body : ::String,
                                            prefix : ::String,
                                            import_modules : Hash(::String, Tuple(::String, Int32)),
                                            mapping : Hash(::String, Hash(::String, ::String)))
      handlers_match = body.match(/route_handlers\s*=\s*\[([^\]]*)\]/m)
      return unless handlers_match

      handlers_match[1].scan(DOTTED_HANDLER_RE) do |handler_match|
        next if handler_match.size < 3
        module_name = handler_match[1]
        handler_name = handler_match[2]
        import_info = import_modules[module_name]?
        next unless import_info

        handler_path = import_info.first
        next if handler_path.empty?

        mapping[handler_path][handler_name] = prefix
      end
    end

    private def collect_controller_prefixes(lines : Array(::String)) : Hash(::String, ::String)
      prefixes = Hash(::String, ::String).new

      lines.each_with_index do |line, idx|
        next unless line.includes?("class")
        class_match = line.match(CONTROLLER_CLASS_RE)
        next unless class_match

        class_name = class_match[1]
        bases = class_match[2]
        next unless bases.includes?("Controller")

        prefix = ""
        if path_match = bases.match(/path\s*=\s*[rf]?['"]([^'"]*)['"]/)
          prefix = path_match[1]
        end

        class_indent = line.size - line.lstrip.size
        class_attr_indent = class_indent + INDENTATION_SIZE
        body_idx = idx + 1
        while body_idx < lines.size
          body_line = lines[body_idx]
          unless body_line.strip.empty?
            indent = body_line.size - body_line.lstrip.size
            break if indent <= class_indent
            stripped = body_line.lstrip
            break if indent == class_attr_indent && (stripped.starts_with?("@") || stripped.starts_with?("def ") || stripped.starts_with?("async def "))

            if indent == class_attr_indent
              if path_attr = body_line.match(/^\s*path\s*=\s*[rf]?['"]([^'"]*)['"]/)
                prefix = path_attr[1]
                break
              end
            end
          end
          body_idx += 1
        end

        prefixes[class_name] = prefix
      end

      prefixes
    end

    private def controller_for_handler(lines : Array(::String),
                                       handler_line : Int32,
                                       controller_prefixes : Hash(::String, ::String)) : Tuple(::String, ::String)?
      handler_indent = lines[handler_line].size - lines[handler_line].lstrip.size
      idx = handler_line - 1

      while idx >= 0
        line = lines[idx]
        unless line.strip.empty?
          indent = line.size - line.lstrip.size
          if indent < handler_indent
            if line.includes?("class") && (class_match = line.match(CLASS_HEAD_RE))
              class_name = class_match[1]
              if controller_prefixes.has_key?(class_name)
                return {class_name, controller_prefixes[class_name]}
              end
            end
          end
        end
        idx -= 1
      end

      nil
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

    # Parse the handler function parameters and its body to collect
    # query/header/cookie/body params. `codeblock` is the pre-parsed
    # handler body (caller-side `parse_code_block(lines[def..])`), so
    # the analyze loop can share one parse between this and the
    # `build_callees_from` path instead of re-parsing here.
    private def extract_handler_params(lines : Array(::String), def_line_index : Int32, route_path : ::String, codeblock : ::String?) : Array(Param)
      params = [] of Param

      function_def = parse_function_def(lines, def_line_index)
      if function_def
        path_param_names = Set(::String).new
        route_path.scan(PATH_PARAM_REGEX) do |m|
          path_param_names << m[1]
        end

        function_def.params.each do |fp|
          name = fp.name.strip
          next if name.empty? || name == "self" || name == "cls" || name == "*" || name == "request"
          next if name.starts_with?("*")
          next if path_param_names.includes?(name)
          next if litestar_dependency_param?(fp)

          type_hint = fp.type.strip
          param_type = classify_param(type_hint)
          next if param_type.nil?

          param_name = name
          # Header/Cookie can override the name via Header("X-Token")
          if type_hint.includes?("Header(") || type_hint.includes?("Cookie(")
            name_match = type_hint.match(/(?:Header|Cookie)\(\s*[rf]?['"]([^'"]+)['"]/)
            param_name = name_match[1] if name_match
          end

          add_unique(params, Param.new(param_name, "", param_type))
        end
      end

      if codeblock
        codeblock.split("\n").each do |cl|
          collect_request_attr_params(cl, "query_params", "query", params)
          collect_request_attr_params(cl, "path_params", "path", params)
          collect_request_attr_params(cl, "headers", "header", params)
          collect_request_attr_params(cl, "cookies", "cookie", params)
        end
      end

      params
    end

    # Map a Litestar parameter type annotation to a noir param type.
    # Returns nil for types that don't warrant a param (Request, State, etc.).
    private def classify_param(type_hint : ::String) : ::String?
      return "query" if type_hint.empty?

      stripped = type_hint
      stripped = stripped.split("Annotated[", 2)[-1].split(",", 2)[-1] if stripped.includes?("Annotated[")

      return if stripped.matches?(/\b(Request|State|Dependency|Provide|WebSocket|WebsocketListener)\b/)
      return "cookie" if stripped.includes?("Cookie")
      return "header" if stripped.includes?("Header")
      return "form" if stripped.includes?("UploadFile") || stripped.includes?("File(")
      return "json" if stripped.includes?("Body")
      return "query" if stripped.includes?("Parameter") || stripped.includes?("Query")

      PRIMITIVE_TYPE_PATTERNS.each do |t_re|
        return "query" if stripped.matches?(t_re)
      end

      # Pydantic/msgspec/dataclass models are treated as request body
      return "json" if stripped.match(/^[A-Z][A-Za-z0-9_]*/)

      nil
    end

    private def litestar_dependency_param?(param : FunctionParameter) : Bool
      litestar_dependency_expression?(param.default) ||
        litestar_dependency_expression?(param.type)
    end

    private def litestar_dependency_expression?(expression : ::String) : Bool
      expression.includes?("Dependency(") || expression.includes?("Provide(")
    end

    private def collect_request_attr_params(line : ::String, attr : ::String, noir_type : ::String, params : Array(Param))
      # The attr substring is a necessary condition for either pattern,
      # so most lines skip the regex matches entirely.
      return unless line.includes?(attr)
      bracket_re, get_re = REQUEST_ATTR_PATTERNS[attr]
      line.scan(bracket_re) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
      line.scan(get_re) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
    end

    private def add_unique(params : Array(Param), param : Param)
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end

    # When `line` is the start of a Litestar route decorator with an
    # unbalanced opening paren, join continuation lines until the
    # matching `)` so the `[^)]*` body capture in `DECORATOR_REGEX`
    # actually sees the path string. No-op for the common single-line
    # form. Newlines in the join are collapsed to spaces so the
    # body-side path/method scans don't have to special-case them.
    private def coalesce_litestar_decorator(lines : Array(::String),
                                            index : Int32,
                                            line : ::String) : ::String
      return line unless line.matches?(/@(?:get|post|put|patch|delete|head|options|route|websocket(?:_listener|_stream)?)\s*\(/)
      delta = python_decorator_paren_delta(line)
      return line if delta <= 0

      pieces = [line]
      i = index + 1
      while i < lines.size && delta > 0
        nxt = lines[i]
        pieces << nxt
        delta += python_decorator_paren_delta(nxt)
        break if delta <= 0
        i += 1
      end
      pieces.join(' ')
    end

    # Net `(` − `)` count, ignoring parens inside string literals on
    # the same line. Single-quote / double-quote with backslash escape
    # are recognized; triple-quoted strings on decorator lines are
    # vanishingly rare in real code.
    private def python_decorator_paren_delta(line : ::String) : Int32
      depth = 0
      in_quote = nil
      escaped = false
      line.each_char do |ch|
        if in_quote
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
        when '('
          depth += 1
        when ')'
          depth -= 1
        end
      end
      depth
    end
  end
end
