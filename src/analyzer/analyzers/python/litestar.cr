require "../../engines/python_engine"

module Analyzer::Python
  class Litestar < PythonEngine
    # Decorator matching: @get("/path"), @post("/path"), etc. The tail
    # after the path literal is captured so extra kwargs (like methods=)
    # can be inspected for multi-method @route decorators.
    DECORATOR_REGEX = /@(get|post|put|patch|delete|head|options|route)\s*\(([^)]*)/
    # Path literal inside a decorator. Litestar accepts both a positional
    # path and an explicit `path=` keyword argument.
    DECORATOR_PATH_REGEX    = /^\s*[rf]?['"]([^'"]*)['"]/
    DECORATOR_PATH_KW_REGEX = /path\s*=\s*[rf]?['"]([^'"]*)['"]/
    HTTP_METHOD_KW_REGEX    = /http_method\s*=\s*\[([^\]]*)\]/
    # Router(path="/prefix", route_handlers=[...])
    ROUTER_REGEX = /(#{PYTHON_VAR_NAME_REGEX})\s*=\s*Router\s*\(([^)]*)/
    # Path param: {name} or {name:type}. Litestar uses the :type suffix
    # as a converter (int, str, uuid, path, float); strip it when
    # exposing the param.
    PATH_PARAM_REGEX       = /\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[a-zA-Z_][a-zA-Z0-9_]*)?\}/
    TYPED_PATH_PARAM_REGEX = /\{([a-zA-Z_][a-zA-Z0-9_]*):[a-zA-Z_][a-zA-Z0-9_]*\}/

    def analyze
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")

          source = read_file_content(path)
          next unless source.includes?("litestar")

          analyze_file(path, source)
        end
      end

      Fiber.yield
      result
    end

    private def analyze_file(path : ::String, source : ::String)
      lines = source.split("\n")
      router_prefixes = collect_router_prefixes(lines)
      handler_routers = collect_handler_to_router(lines, router_prefixes)

      lines.each_with_index do |line, line_index|
        line.scan(DECORATOR_REGEX) do |match|
          next if match.size < 3
          decorator = match[1].downcase
          body = match[2]

          path_match = body.match(DECORATOR_PATH_REGEX) || body.match(DECORATOR_PATH_KW_REGEX)
          next unless path_match
          route_path = path_match[1]

          methods = [] of ::String
          if decorator == "route"
            http_match = body.match(HTTP_METHOD_KW_REGEX)
            if http_match
              http_match[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
                methods << m[1].upcase
              end
            end
            methods << "GET" if methods.empty?
          else
            methods << decorator.upcase
          end

          handler_name, handler_line = find_handler(lines, line_index)
          prefix = handler_name ? handler_routers[handler_name]? || "" : ""

          full_path = "#{prefix}#{route_path}"
          full_path = "/#{full_path}" unless full_path.starts_with?("/")
          full_path = full_path.gsub(/\/+/, "/")
          full_path = full_path.gsub(TYPED_PATH_PARAM_REGEX) { |_| "{#{$~[1]}}" }

          path_params = extract_path_params(route_path)
          handler_params = handler_line ? extract_handler_params(lines, handler_line, route_path) : [] of Param

          methods.uniq.each do |method|
            params = [] of Param
            path_params.each { |p| params << p }
            handler_params.each do |p|
              next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
              params << p
            end

            details = Details.new(PathInfo.new(path, line_index + 1))
            result << Endpoint.new(full_path, method, params, details)
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
    private def collect_router_prefixes(lines : Array(::String)) : Hash(::String, ::String)
      prefixes = Hash(::String, ::String).new
      lines.each do |line|
        line.scan(ROUTER_REGEX) do |match|
          next if match.size < 3
          name = match[1]
          body = match[2]
          prefix_match = body.match(/path\s*=\s*[rf]?['"]([^'"]*)['"]/)
          prefix_match ||= body.match(/^\s*[rf]?['"]([^'"]*)['"]/)
          prefixes[name] = prefix_match ? prefix_match[1] : ""
        end
      end
      prefixes
    end

    # Walk each Router(...) block and map handler-function names in
    # route_handlers to the router's prefix, so handler endpoints inherit
    # the prefix when the route is registered on a Router.
    private def collect_handler_to_router(lines : Array(::String), router_prefixes : Hash(::String, ::String)) : Hash(::String, ::String)
      mapping = Hash(::String, ::String).new
      source = lines.join("\n")
      source.scan(/(#{PYTHON_VAR_NAME_REGEX})\s*=\s*Router\s*\(([^)]*)\)/m) do |match|
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
      mapping
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
    # query/header/cookie/body params.
    private def extract_handler_params(lines : Array(::String), def_line_index : Int32, route_path : ::String) : Array(Param)
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

      codeblock = parse_code_block(lines[def_line_index..])
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

      return if stripped.matches?(/\b(Request|State|Dependency|Provide|WebSocket)\b/)
      return "cookie" if stripped.includes?("Cookie")
      return "header" if stripped.includes?("Header")
      return "form" if stripped.includes?("UploadFile") || stripped.includes?("File(")
      return "json" if stripped.includes?("Body")
      return "query" if stripped.includes?("Parameter")

      primitive_types = ["str", "int", "float", "bool", "bytes", "UUID", "date", "datetime"]
      primitive_types.each do |t|
        return "query" if stripped.matches?(/\b#{t}\b/)
      end

      # Pydantic/msgspec/dataclass models are treated as request body
      return "json" if stripped.match(/^[A-Z][A-Za-z0-9_]*/)

      nil
    end

    private def collect_request_attr_params(line : ::String, attr : ::String, noir_type : ::String, params : Array(Param))
      line.scan(/request\.#{attr}\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
      line.scan(/request\.#{attr}\.get\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
    end

    private def add_unique(params : Array(Param), param : Param)
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end
  end
end
