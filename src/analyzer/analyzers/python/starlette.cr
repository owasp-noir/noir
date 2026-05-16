require "../../engines/python_engine"

module Analyzer::Python
  class Starlette < PythonEngine
    # Route('/path', handler, methods=[...]) — captures path, and the tail
    # after the path literal so we can inspect methods= and the handler
    # reference. The tail stops at the closing paren on the same line to
    # keep the match cheap; multi-line Route() calls are still covered for
    # the common (path, handler, methods) shape.
    ROUTE_REGEX = /Route\s*\(\s*[rf]?['"]([^'"]*)['"]([^)]*)/
    # Mount('/prefix', routes=[...]) — only the prefix literal is needed;
    # the routes list is scanned via the ongoing line loop while the mount
    # is on the paren stack.
    MOUNT_REGEX = /Mount\s*\(\s*[rf]?['"]([^'"]*)['"]/
    # Path param in a route pattern: {name} or {name:type}. Starlette uses
    # the :type suffix as a converter hint (int, str, float, uuid, path);
    # it is stripped before the param is exposed as a path param.
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
      handler_cache = {} of ::String => Tuple(Array(Param), Array(Callee))
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
        effective_line = if line.includes?("Route") && python_paren_delta(line) > 0
                           join_until_python_call_closes(lines, line_index, line)
                         else
                           line
                         end
        # Lift `path=` keyword to the first positional slot so the
        # existing ROUTE_REGEX (which expects a string right after
        # `Route(`) matches `Route(path="/x", endpoint=h)`.
        effective_line = effective_line.gsub(/(Route\s*\()\s*path\s*=\s*([rf]?['"][^'"]*['"])/, "\\1\\2,")

        effective_line.scan(MOUNT_REGEX) do |match|
          next if match.size < 2
          mount_stack << {match[1], paren_depth + 1}
        end

        effective_line.scan(ROUTE_REGEX) do |match|
          next if match.size < 3
          route_path = match[1]
          tail = match[2]

          methods = [] of ::String
          methods_match = tail.match(/methods\s*=\s*\[([^\]]*)\]/)
          if methods_match
            methods_match[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
              methods << m[1].upcase
            end
          end
          methods << "GET" if methods.empty?

          prefix = mount_stack.map(&.[0]).join
          full_url = "#{prefix}#{route_path}"
          full_url = "/#{full_url}".gsub(/\/+/, "/")
          full_url = full_url.gsub(TYPED_PATH_PARAM_REGEX) { |_| "{#{$~[1]}}" }

          path_params = extract_path_params(route_path)

          handler_params = [] of Param
          handler_callees = [] of Callee
          handler_name = nil
          if endpoint_keyword_match = tail.match(/endpoint\s*=\s*([a-zA-Z_][a-zA-Z0-9_]*)/)
            handler_name = endpoint_keyword_match[1]
          elsif positional_match = tail.match(/,\s*([a-zA-Z_][a-zA-Z0-9_]*)/)
            handler_name = positional_match[1]
          end
          if handler_name
            handler_params, handler_callees = handler_context_for(lines, function_index, handler_name, path, handler_cache,
              definition_base_path: definition_base_path, source: source)
          end

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

        paren_depth += line.count('(') - line.count(')')
        paren_depth = 0 if paren_depth < 0
        while !mount_stack.empty? && mount_stack.last[1] > paren_depth
          mount_stack.pop
        end
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

      codeblock.split("\n").each do |cl|
        collect_request_attr_params(cl, request_name, "path_params", "path", params)
        collect_request_attr_params(cl, request_name, "query_params", "query", params)
        collect_request_attr_params(cl, request_name, "headers", "header", params)
        collect_request_attr_params(cl, request_name, "cookies", "cookie", params)

        if cl.matches?(/await\s+#{Regex.escape(request_name)}\.json\s*\(/)
          add_unique(params, Param.new("body", "", "json"))
        end
        if cl.matches?(/await\s+#{Regex.escape(request_name)}\.form\s*\(/)
          add_unique(params, Param.new("body", "", "form"))
        end
      end

      callees = build_callees_from(codeblock, idx, path,
        definition_base_path: definition_base_path, source: source)
      cache[handler_name] = {params, callees}
      cache[handler_name]
    end

    private def collect_request_attr_params(line : ::String, request_name : ::String, attr : ::String, noir_type : ::String, params : Array(Param))
      line.scan(/#{Regex.escape(request_name)}\.#{attr}\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
      line.scan(/#{Regex.escape(request_name)}\.#{attr}\.get\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
    end

    private def add_unique(params : Array(Param), param : Param)
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end
  end
end
