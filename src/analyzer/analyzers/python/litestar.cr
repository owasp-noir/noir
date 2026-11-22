require "../../engines/python_engine"
require "./python_helper"

module Analyzer::Python
  class Litestar < PythonEngine
    analyzer_for "python_litestar"

    # Decorator matching: @get("/path"), @post("/path"), etc. The tail
    # after the path literal is captured so extra kwargs (like methods=)
    # can be inspected for multi-method @route decorators.
    # `websocket(?:_listener|_stream)?` also matches Litestar's
    # `@websocket_listener("/ws")` and `@websocket_stream("/ws")`
    # decorators (the listener/stream class-based WS handlers), which
    # take a positional path just like `@websocket` — without the
    # variants every listener/stream endpoint was silently dropped.
    DECORATOR_REGEX = /@(get|post|put|patch|delete|head|options|route|websocket(?:_listener|_stream)?)\s*\((#{PYTHON_CALL_ARGS})/
    # Path literal inside a decorator. Litestar accepts both a positional
    # path and an explicit `path=` keyword argument. List forms
    # (`@get(["/a", "/b"])`, `@get(path=["/a", "/b"])`) and omitted paths
    # (`@get()`, `@get(sync_to_thread=False)` → default `""` / `/`) are
    # handled by `extract_decorator_paths`.
    DECORATOR_PATH_REGEX      = /^\s*[rf]?['"]([^'"]*)['"]/
    DECORATOR_PATH_KW_REGEX   = /path\s*=\s*[rf]?['"]([^'"]*)['"]/
    DECORATOR_PATH_LIST_REGEX = /^\s*\[([^\]]*)\]/
    DECORATOR_PATH_LIST_KW_RE = /path\s*=\s*\[([^\]]*)\]/
    HTTP_METHOD_KW_REGEX      = /http_method\s*=\s*(?:[\[(]([^\])]*)[\])]|['"]([^'"]+)['"]|HttpMethod\.([A-Za-z]+))/
    # One verb in an `http_method=[...]` list: `"POST"` or `HttpMethod.POST`.
    HTTP_METHOD_ITEM_REGEX = /['"]([A-Za-z]+)['"]|HttpMethod\.([A-Za-z]+)/
    # `Parameter(header="X-Token")` / `cookie=` / `query=`: the location
    # and wire name, in a default or an `Annotated[...]` hint.
    PARAMETER_LOCATION_REGEX = /\bParameter\s*\((?:[^()'"]|'[^']*'|"[^"]*"|\([^()]*\))*?\b(header|cookie|query)\s*=\s*[rf]?['"]([^'"]+)['"]/
    # The same, as the whole default: `x: str = Parameter(header="X")`.
    # Anchored, so a long default is not searched end to end.
    PARAMETER_DEFAULT_LOCATION_REGEX = /\A\s*#{PARAMETER_LOCATION_REGEX}/
    # Hoisted out of the per-line/per-param loops: an interpolated regex
    # literal recompiles (PCRE2 JIT) on every evaluation, and these
    # interpolate only constants or fixed sets. The `.to_s` expansion is
    # byte-identical to the previous inline form, so matching behaviour
    # is unchanged.
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

    # Names a `dependencies` mapping provides (`"users_service":
    # Provide(...)`, or a service helper's `key="users_service"` inside the
    # `dependencies = ...` statement): a handler parameter so named is
    # injected, not read from the request. Keys count for handlers in the
    # declaring file, or everywhere when that file builds the `Litestar(...)`
    # app (app-level dependencies).
    # ponytail: file scope, not Litestar's handler/controller/router scope;
    # a same-named query param in another controller of that file is
    # dropped too.
    PROVIDE_KEY_RE       = /['"]([A-Za-z_]\w*)['"]\s*:\s*Provide\s*\(/
    DEPENDENCIES_LINE_RE = /\bdependencies\s*[:=]/
    DEPENDENCY_KEY_RE    = /\bkey\s*=\s*['"]([A-Za-z_]\w*)['"]/
    LITESTAR_APP_RE      = /\bLitestar\s*\(/
    BODY_MODEL_RE        = /\A\s*([A-Z][A-Za-z0-9_]*)\s*\z/
    MODEL_FIELD_RE       = /^([A-Za-z_]\w*)\s*:\s*(.+)$/
    FORM_ENCODING_RE     = /RequestEncodingType\.(?:URL_ENCODED|MULTI_PART)/
    # Bases a body model's own fields are complete under; any other base
    # may contribute fields this pass does not follow.
    MODEL_ROOT_BASES = Set{"BaseModel", "Struct", "msgspec.Struct", "pydantic.BaseModel", "object", "TypedDict"}
    # `"file\0name"` of a handler, controller or router -> its prefixes.
    @handler_prefixes = Hash(::String, Array(::String)).new
    @dependency_keys = Hash(::String, Set(::String)).new
    @app_dependency_keys = Set(::String).new
    @model_fields = Hash(Tuple(::String, ::String), Array(::String)?).new
    @model_fields_mutex = Mutex.new

    def analyze
      edges = [] of Tuple(::String, ::String, ::String)
      routers = Set(::String).new

      # Pass 1 (sequential): the project-wide router graph.
      each_python_source do |path, current_base_path|
        source = read_file_content(path)
        next unless source.includes?("litestar")

        collect_dependency_keys(path, source)
        collect_router_edges(path, current_base_path, source, routers, edges)
      end
      children = edges.map(&.[2]).to_set
      routers.each { |router| @handler_prefixes[router] = [""] unless children.includes?(router) }
      propagate_mount_prefixes(@handler_prefixes, edges) { |parent_prefix, router_path| "#{parent_prefix}#{router_path}" }

      # Pass 2 (parallel): per-file route extraction is independent once
      # the prefix map is frozen.
      parallel_python_sources do |path, current_base_path|
        source = read_file_content(path)
        next unless source.includes?("litestar")

        analyze_file(path, source, current_base_path)
      end

      Fiber.yield
      result
    end

    private def analyze_file(path : ::String,
                             source : ::String,
                             definition_base_path : ::String)
      lines = source.split("\n")
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

          # One or more route paths: scalar literal, list, or default "".
          route_paths = extract_decorator_paths(body)

          methods = [] of ::String
          websocket_route = decorator.starts_with?("websocket")
          if decorator == "route"
            http_match = body.match(HTTP_METHOD_KW_REGEX)
            if http_match
              if list_content = http_match[1]?
                list_content.scan(HTTP_METHOD_ITEM_REGEX) { |m| methods << (m[1]? || m[2]).upcase }
              elsif single_method = http_match[2]? || http_match[3]?
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
          prefixes = handler_name ? litestar_prefixes(path, handler_name) : [""]
          if hl = handler_line
            if controller_info = controller_for_handler(lines, hl, controller_prefixes)
              controller_name, controller_prefix = controller_info
              prefixes = litestar_prefixes(path, controller_name).map { |prefix| "#{prefix}#{controller_prefix}" }
            end
          end

          # Parse the handler body once and share between param and
          # callee extraction — both used to call `parse_code_block`
          # independently, costing 2 parses per handler. Shared across
          # multi-path list decorators (same handler, several paths).
          handler_body = if hl = handler_line
                           parse_code_block(lines[hl..])
                         end

          # Build once per handler — a decorator can emit multiple
          # endpoints when @route(http_method=[...]) lists several verbs
          # and/or when path is a list of strings.
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

          prefixes.flat_map { |prefix| route_paths.map { |route_path| "#{prefix}#{route_path}" } }.uniq!.each do |full_path|
            full_path = Noir::URLPath.normalize(full_path, collapse: true)
            # `{p:path}` stays: it spans `/`, so it is not `{p}`.
            full_path = Noir::URLPath.strip_type_converters(full_path)

            path_params = Noir::URLPath.params(full_path, Noir::URLPath::BRACE_CONVERTER, unique: true)
            handler_params = handler_line ? extract_handler_params(lines, handler_line, full_path, handler_body, source, path, definition_base_path) : [] of Param

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
    end

    # Resolve the path argument(s) of a Litestar HTTP/WS decorator body.
    # Returns at least one path string. An omitted path defaults to `""`
    # (Litestar joins it with the controller prefix, or yields `/` when
    # bare) so `@get()` / `@get(sync_to_thread=False)` are not dropped.
    private def extract_decorator_paths(body : ::String) : Array(::String)
      if list_match = body.match(DECORATOR_PATH_LIST_REGEX) || body.match(DECORATOR_PATH_LIST_KW_RE)
        paths = [] of ::String
        list_match[1].scan(/[rf]?['"]([^'"]*)['"]/) { |m| paths << m[1] }
        return paths unless paths.empty?
      end

      if path_match = body.match(DECORATOR_PATH_REGEX) || body.match(DECORATOR_PATH_KW_REGEX)
        return [path_match[1]]
      end

      [""]
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

    # A `X = Router(` / `Litestar(` call (or a bare `Router(`), up to its `(`.
    ROUTER_CALL_RE   = /(?:\b(#{PYTHON_VAR_NAME_REGEX})\s*(?::[^=\n]*)?=\s*)?\b(Router|Litestar)\s*\(/
    HANDLER_REF_RE   = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/
    INLINE_ROUTER_RE = /\ARouter\s*\(/

    # Record every `Router(...)` / `Litestar(...)` call of `path` as a node
    # `"file\0name"` (`"file\0@offset"` when unassigned), with an edge
    # {router, router path, entry} per `route_handlers` entry. An entry is
    # resolved to where it is declared: a local name, a name imported from
    # another module, `module.name`, or an inline `Router(...)`.
    private def collect_router_edges(path : ::String, base_path : ::String, source : ::String,
                                     routers : Set(::String), edges : Array(Tuple(::String, ::String, ::String))) : Nil
      return unless source.includes?("Router") || source.includes?("Litestar")
      symbols = nil
      call_end = -1
      source.scan(ROUTER_CALL_RE) do |match|
        next if match.byte_begin(0) < call_end
        open = match.byte_end(0) - 1
        body = python_call_body(source, open) || next
        call_end = open + body.bytesize + 1
        symbols ||= Noir::ImportGraph::Python.find_imported_symbols(base_path, path, source)
        node = "#{path}\0#{match[1]? || "@#{match.byte_begin(0)}"}"
        record_router_node(path, node, match[2] == "Litestar", body, symbols, routers, edges)
      end
    end

    private def record_router_node(path : ::String, node : ::String, app : Bool, body : ::String,
                                   symbols : Hash(::String, Tuple(::String, ::String)),
                                   routers : Set(::String), edges : Array(Tuple(::String, ::String, ::String))) : Nil
      routers << node
      args = split_python_arguments(body)
      router_path = app ? "" : extract_python_keyword_string(args, "path") || args[0]?.try { |arg| Helper.extract_python_string(arg) } || ""
      handlers = extract_python_keyword_expression(args, "route_handlers") || return
      return unless handlers.starts_with?('[') && handlers.ends_with?(']')
      split_python_arguments(handlers[1...-1]).each_with_index do |raw_entry, index|
        entry = raw_entry.strip
        if entry.matches?(INLINE_ROUTER_RE) && entry.ends_with?(')')
          child = "#{node}/#{index}"
          record_router_node(path, child, false, entry.sub(INLINE_ROUTER_RE, "")[0...-1], symbols, routers, edges)
        else
          child = litestar_handler_node(path, entry, symbols) || next
        end
        edges << {node, router_path, child}
      end
    end

    private def litestar_handler_node(path : ::String, entry : ::String,
                                      symbols : Hash(::String, Tuple(::String, ::String))) : ::String?
      return unless entry.matches?(HANDLER_REF_RE)
      if dot = entry.rindex('.')
        target = symbols[entry[0, dot]]? || return
        return target[1].empty? ? "#{target[0]}\0#{entry[(dot + 1)..]}" : nil
      end
      if (target = symbols[entry]?) && !target[1].empty?
        "#{target[0]}\0#{target[1]}"
      else
        "#{path}\0#{entry}"
      end
    end

    # The text between the `(` at byte `open` and its matching `)`,
    # skipping quoted runs and `#` comments.
    private def python_call_body(source : ::String, open : Int32) : ::String?
      bytes = source.to_slice
      depth = 0
      quote = 0_u8
      i = open
      while i < bytes.size
        byte = bytes[i]
        if quote != 0
          if byte == '\\'.ord
            i += 1
          elsif byte == quote
            quote = 0_u8
          end
        elsif byte == '"'.ord || byte == '\''.ord
          quote = byte
        elsif byte == '#'.ord
          while i + 1 < bytes.size && bytes[i + 1] != '\n'.ord
            i += 1
          end
        elsif byte == '('.ord
          depth += 1
        elsif byte == ')'.ord
          depth -= 1
          return source.byte_slice(open + 1, i - open - 1) if depth == 0
        end
        i += 1
      end
    end

    # Full prefixes a handler or controller named `name` in `path` is
    # served under, through every router that lists it.
    private def litestar_prefixes(path : ::String, name : ::String) : Array(::String)
      @handler_prefixes["#{path}\0#{name}"]? || [""]
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
      # A module-level handler has no enclosing class: walking back to the
      # top of the file for each one made a flat routes module quadratic.
      return if handler_indent == 0 || controller_prefixes.empty?
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

    private def collect_dependency_keys(path : ::String, source : ::String) : Nil
      return unless source.includes?("Provide") || source.includes?("dependencies")
      keys = Set(::String).new
      source.scan(PROVIDE_KEY_RE) { |m| keys << m[1] }
      lines = source.split("\n")
      lines.each_with_index do |line, index|
        next unless line.includes?("dependencies") && line.matches?(DEPENDENCIES_LINE_RE)
        join_until_python_call_closes(lines, index, line).scan(DEPENDENCY_KEY_RE) { |m| keys << m[1] }
      end
      return if keys.empty?
      @dependency_keys[path] = keys
      @app_dependency_keys.concat(keys) if source.matches?(LITESTAR_APP_RE)
    end

    private def dependency_key?(path : ::String, name : ::String) : Bool
      @app_dependency_keys.includes?(name) || !!@dependency_keys[path]?.try(&.includes?(name))
    end

    # Litestar's `data` argument is the request body: its type's fields are
    # the params. Nil when the type is not a class found in this file or
    # one it imports.
    private def litestar_data_params(type_hint : ::String, default : ::String, source : ::String, path : ::String,
                                     base_path : ::String) : Array(Param)?
      location = type_hint.matches?(FORM_ENCODING_RE) || default.matches?(FORM_ENCODING_RE) ? "form" : "json"
      hint = type_hint.includes?("Annotated[") ? type_hint.split("Annotated[", 2)[1].split(',', 2)[0] : type_hint
      model = hint.match(BODY_MODEL_RE).try(&.[1]) || return
      fields = if source.includes?("class #{model}")
                 model_field_names(path, source, model)
               elsif imported = find_imported_modules(base_path, path, source)[model]?
                 model_field_names(imported[0], read_file_content(imported[0]), model)
               end
      fields.try(&.map { |name| Param.new(name, "", location) })
    end

    # Annotated class-body attributes of `class model` in `file`. Nil, so
    # the caller keeps a plain `data` param, when the class is not found,
    # declares no field of its own, or has a base that may add fields.
    private def model_field_names(file : ::String, source : ::String, model : ::String) : Array(::String)?
      key = {file, model}
      @model_fields_mutex.synchronize { return @model_fields[key] if @model_fields.has_key?(key) }
      fields = read_model_field_names(source, model)
      @model_fields_mutex.synchronize { @model_fields[key] = fields }
      fields
    end

    private def read_model_field_names(source : ::String, model : ::String) : Array(::String)?
      return unless source.includes?("class #{model}")
      lines = source.split("\n")
      header_re = /^\s*class\s+#{Regex.escape(model)}\s*(?:\(([^)]*)\))?\s*:/
      class_index = lines.index { |line| line.includes?(model) && line.matches?(header_re) } || return
      header = lines[class_index].match(header_re) || return
      if bases = header[1]?
        return unless bases.split(',').map(&.strip).reject(&.empty?).all? { |base| MODEL_ROOT_BASES.includes?(base) }
      end
      class_indent = lines[class_index].size - lines[class_index].lstrip.size
      in_docstring = Helper.docstring_line_flags(lines)
      body_indent = nil
      names = [] of ::String
      ((class_index + 1)...lines.size).each do |i|
        stripped = lines[i].lstrip
        next if stripped.empty? || stripped.starts_with?('#') || in_docstring[i]
        indent = lines[i].size - stripped.size
        break if indent <= class_indent
        body_indent ||= indent
        next unless indent == body_indent
        next unless field = stripped.match(MODEL_FIELD_RE)
        next if field[2].lstrip.starts_with?("ClassVar")
        names << field[1]
      end
      names.empty? ? nil : names
    end

    # Parse the handler function parameters and its body to collect
    # query/header/cookie/body params. `codeblock` is the pre-parsed
    # handler body (caller-side `parse_code_block(lines[def..])`), so
    # the analyze loop can share one parse between this and the
    # `build_callees_from` path instead of re-parsing here.
    private def extract_handler_params(lines : Array(::String), def_line_index : Int32, route_path : ::String, codeblock : ::String?,
                                       source : ::String = "", path : ::String = "", base_path : ::String = "") : Array(Param)
      params = [] of Param

      function_def = parse_function_def(lines, def_line_index)
      if function_def
        path_param_names = Noir::URLPath.names(route_path, Noir::URLPath::BRACE_CONVERTER).to_set

        function_def.params.each do |fp|
          name = fp.name.strip
          next if name.empty? || name == "self" || name == "cls" || name == "*" || name == "request"
          next if name.starts_with?("*")
          next if path_param_names.includes?(name)
          next if litestar_dependency_param?(fp) || dependency_key?(path, name)

          type_hint = fp.type.strip
          if name == "data" && (body = litestar_data_params(type_hint, fp.default, source, path, base_path))
            body.each { |param| add_unique(params, param) }
            next
          end
          if location = type_hint.match(PARAMETER_LOCATION_REGEX) || fp.default.match(PARAMETER_DEFAULT_LOCATION_REGEX)
            add_unique(params, Param.new(location[2], "", location[1]))
            next
          end

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
        fold_python_continuations(codeblock.split("\n")).each do |cl|
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
    # matching `)` so the body capture in `DECORATOR_REGEX`
    # actually sees the path string. No-op for the common single-line
    # form. Newlines in the join are collapsed to spaces so the
    # body-side path/method scans don't have to special-case them.
    private def coalesce_litestar_decorator(lines : Array(::String),
                                            index : Int32,
                                            line : ::String) : ::String
      return line unless line.matches?(/@(?:get|post|put|patch|delete|head|options|route|websocket(?:_listener|_stream)?)\s*\(/)
      return line if python_paren_delta(line) <= 0

      join_until_python_call_closes(lines, index, line)
    end
  end
end
