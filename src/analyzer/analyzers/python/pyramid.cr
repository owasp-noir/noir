require "../../engines/python_engine"

module Analyzer::Python
  class Pyramid < PythonEngine
    # Reference: https://docs.pylonsproject.org/projects/pyramid/en/latest/narr/urldispatch.html
    #
    # Pyramid wires requests in two steps:
    #
    #   1. `config.add_route("name", "/path/{id}")` — declares a named route
    #      with a path pattern. Path parameters use `{name}` syntax.
    #
    #   2. A view is attached to that route either declaratively via
    #      `@view_config(route_name="name", request_method="GET")` on a
    #      function, or imperatively via
    #      `config.add_view(view, route_name="name", request_method="POST")`.
    #
    # The analyzer runs in two passes per file: first it builds a route
    # name→path map from `add_route` calls, then it walks view bindings
    # and emits endpoints, extracting request parameters from the
    # decorated function body.
    #
    # Parameter accessors on `request`:
    #   request.matchdict["id"]                    → path (but we already
    #                                                have those from the URL)
    #   request.GET / request.params["k"]          → query
    #   request.POST["k"]                          → form
    #   request.json_body["k"] / request.json["k"] → json
    #   request.headers["X-Foo"]                   → header
    #   request.cookies["foo"]                     → cookie

    QUERY_ACCESSORS = %w[GET params]
    FORM_ACCESSORS  = %w[POST]
    JSON_ACCESSORS  = %w[json_body json]

    def analyze
      route_map = Hash(String, Tuple(String, String)).new # name => {path, decl_file}

      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")

          content = read_file_content(path)
          next unless content.includes?("pyramid")

          content.each_line do |line|
            # config.add_route("name", "/path") — keyword variants accepted
            if m = line.match(/\.add_route\s*\(\s*[rf]?['"]([^'"]+)['"]\s*,\s*[rf]?['"]([^'"]*)['"]/)
              route_map[m[1]] = {m[2], path}
            end
          end
        end
      end

      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")
          @logger.debug "Analyzing #{path}"

          content = read_file_content(path)
          next unless content.includes?("pyramid")

          lines = content.lines
          lines.each_with_index do |line, line_index|
            # @view_config(route_name="name", request_method="GET")
            if vc = match_view_config(lines, line_index)
              route_name, methods = vc
              next unless route_map.has_key?(route_name)
              route_path, _ = route_map[route_name]

              def_index = find_def_line(lines, line_index)
              next if def_index.nil?

              body = extract_function_body(lines, def_index)
              emit_endpoints(path, line_index, route_path, methods, body)
            end

            # config.add_view(view_func, route_name="name", request_method="POST")
            if av = line.match(/\.add_view\s*\((.+)\)/)
              args = av[1]
              rn_match = args.match(/route_name\s*=\s*[rf]?['"]([^'"]+)['"]/)
              next if rn_match.nil?
              route_name = rn_match[1]
              next unless route_map.has_key?(route_name)
              route_path, _ = route_map[route_name]

              methods = extract_methods_from_args(args)
              methods = ["GET"] if methods.empty?

              view_func_name = extract_view_func(args)
              body = ""
              if view_func_name && !view_func_name.empty?
                view_def_index = find_function_def(lines, view_func_name)
                body = extract_function_body(lines, view_def_index) unless view_def_index.nil?
              end

              emit_endpoints(path, line_index, route_path, methods, body)
            end
          end
        end
      end

      result
    end

    # Look up `@view_config(...)` either on a single line or across
    # continuation lines (the decorator call may span multiple lines).
    # Returns {route_name, methods} or nil.
    private def match_view_config(lines : Array(String), line_index : Int32) : Tuple(String, Array(String))?
      stripped = lines[line_index].lstrip
      return unless stripped.starts_with?("@view_config") || stripped.starts_with?("@pyramid.view.view_config")

      decorator = stripped
      idx = line_index
      paren_open = decorator.count('(')
      paren_close = decorator.count(')')
      while paren_open > paren_close && idx + 1 < lines.size
        idx += 1
        decorator += lines[idx]
        paren_open = decorator.count('(')
        paren_close = decorator.count(')')
      end

      rn_match = decorator.match(/route_name\s*=\s*[rf]?['"]([^'"]+)['"]/)
      return if rn_match.nil?
      route_name = rn_match[1]

      methods = extract_methods_from_args(decorator)
      methods = ["GET"] if methods.empty?
      {route_name, methods}
    end

    # Pull request_method= or request_method=['GET','POST'] out of an
    # argument string. Pyramid uses singular `request_method`; we also
    # accept a list form for convenience.
    private def extract_methods_from_args(args : String) : Array(String)
      methods = [] of String
      if m = args.match(/request_method\s*=\s*['"]([A-Za-z]+)['"]/)
        methods << m[1].upcase
      end
      if m = args.match(/request_method\s*=\s*[\[\(]([^\]\)]+)[\]\)]/)
        m[1].scan(/['"]([A-Za-z]+)['"]/) do |mm|
          methods << mm[1].upcase
        end
      end
      methods.uniq
    end

    # `add_view(view_func, ...)` — the first positional arg is the view
    # callable. Supports bare name and `view=name` keyword form.
    private def extract_view_func(args : String) : String?
      if m = args.match(/view\s*=\s*([A-Za-z_][A-Za-z0-9_]*)/)
        return m[1]
      end
      # First positional token before any `=`-keyword.
      first = args.split(',').first?.try(&.strip)
      return if first.nil? || first.empty?
      return if first.includes?('=')
      return first if first.match(/^[A-Za-z_][A-Za-z0-9_]*$/)
      nil
    end

    # Walk downwards from `line_index` past any further decorators or
    # blank lines until the `def` / `async def` that they decorate.
    private def find_def_line(lines : Array(String), line_index : Int32) : Int32?
      i = line_index + 1
      while i < lines.size
        stripped = lines[i].lstrip
        if stripped.starts_with?("def ") || stripped.starts_with?("async def ")
          return i
        end
        if stripped.empty? || stripped.starts_with?("@")
          i += 1
          next
        end
        # Continuation of a multi-line decorator call.
        i += 1
      end
      nil
    end

    # Locate the first top-level `def <name>` in a file.
    private def find_function_def(lines : Array(String), name : String) : Int32?
      lines.each_with_index do |line, idx|
        stripped = line.lstrip
        if stripped.starts_with?("def #{name}(") || stripped.starts_with?("def #{name} (") ||
           stripped.starts_with?("async def #{name}(") || stripped.starts_with?("async def #{name} (")
          return idx
        end
      end
      nil
    end

    # Collect indented lines following a `def` as the function body.
    private def extract_function_body(lines : Array(String), def_index : Int32) : String
      return "" if def_index >= lines.size
      def_line = lines[def_index]
      base_indent = def_line.size - def_line.lstrip.size

      body = [] of String
      i = def_index + 1
      while i < lines.size
        line = lines[i]
        if line.strip.empty?
          body << line
          i += 1
          next
        end
        current_indent = line.size - line.lstrip.size
        break if current_indent <= base_indent
        body << line
        i += 1
      end
      body.join("\n")
    end

    # Build endpoint(s) for a route+methods combo.
    private def emit_endpoints(path : String, line_index : Int32, route_path : String,
                               methods : Array(String), body : String)
      path_params = extract_path_params(route_path)
      request_params = extract_request_params(body)

      details = Details.new(PathInfo.new(path, line_index + 1))
      methods.each do |method|
        endpoint = Endpoint.new(route_path, method, details)
        path_params.each { |p| endpoint.push_param(p) }
        request_params.each do |p|
          # form/json params only make sense for body-bearing methods; we
          # don't filter here because Pyramid's accessor names already
          # carry the method implication (request.POST → form), and the
          # detector's method list governs which endpoints exist.
          endpoint.push_param(p)
        end
        result << endpoint
      end
    end

    private def extract_path_params(route_path : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new
      # Pyramid path params: `{name}` or `{name:regex}`
      route_path.scan(/\{([A-Za-z_][A-Za-z0-9_]*)(?::[^}]+)?\}/) do |m|
        name = m[1]
        next if seen.includes?(name)
        seen << name
        params << Param.new(name, "", "path")
      end
      params
    end

    private def extract_request_params(body : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      record = ->(name : String, type : String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      scan_accessors = ->(accessors : Array(String), param_type : String) do
        accessors.each do |accessor|
          body.scan(/request\.#{accessor}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
            record.call(m[1], param_type)
          end
          body.scan(/request\.#{accessor}\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
            record.call(m[1], param_type)
          end
        end
      end

      scan_accessors.call(QUERY_ACCESSORS, "query")
      scan_accessors.call(FORM_ACCESSORS, "form")
      scan_accessors.call(JSON_ACCESSORS, "json")

      body.scan(/request\.headers\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "header")
      end
      body.scan(/request\.headers\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "header")
      end

      body.scan(/request\.cookies\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "cookie")
      end
      body.scan(/request\.cookies\.get\s*\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "cookie")
      end

      params
    end
  end
end
