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

    ACCESSOR_MAP = {
      "query"  => ["params", "GET"],
      "form"   => ["POST"],
      "json"   => ["json_body", "json"],
      "header" => ["headers"],
      "cookie" => ["cookies"],
    }

    # `extract_request_params` runs once per endpoint and used to rebuild
    # two PCRE2 patterns per accessor on every call (an interpolated regex
    # literal recompiles on every evaluation). The accessor set is fixed,
    # so precompile the access patterns once here; the `.to_s` expansion
    # is byte-identical to the previous inline form.
    # Tuple shape: {noir_param_type, bracket_re, get_re}
    ACCESSOR_PATTERNS = ACCESSOR_MAP.flat_map do |param_type, accessors|
      accessors.map do |accessor|
        {param_type,
         /(?:self\.)?request\.#{accessor}\s*\[\s*[rf]?['"]([^'"]+)['"]\s*\]/,
         /(?:self\.)?request\.#{accessor}\.get(?:all|one)?\s*\(\s*[rf]?['"]([^'"]+)['"]/}
      end
    end

    @keyword_regex_cache = Hash(String, Regex).new

    alias RouteNameKey = Tuple(String, String)
    alias RouteMap = Hash(RouteNameKey, Tuple(String, String))

    def analyze
      route_map = RouteMap.new # {base_path, name} => {path, decl_file}

      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)

          content = read_file_content(path)
          next unless content.includes?("pyramid") || content.includes?(".add_route") || content.includes?(".add_static_view")

          extract_route_declarations(content, path, route_map, current_base_path)
          extract_static_views(content, path)
        end
      end

      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          content = read_file_content(path)
          next unless content.includes?("pyramid") || content.includes?(".add_view")

          lines = content.lines
          lines.each_with_index do |line, line_index|
            # @view_config(route_name="name", request_method="GET")
            if vc = match_view_config(lines, line_index)
              route_name, methods = vc
              route_name ||= class_view_defaults_route_name(lines, line_index)
              next if route_name.nil?
              route_key = {current_base_path, route_name}
              next unless route_map.has_key?(route_key)
              route_path, _ = route_map[route_key]

              def_index = find_def_line(lines, line_index)
              next if def_index.nil?

              body = extract_function_body(lines, def_index)
              emit_endpoints(path, line_index, route_path, methods, body, def_index,
                definition_base_path: current_base_path, source: content)
            end

            # config.add_view(view_func, route_name="name", request_method="POST")
            # Coalesce continuation lines so the args regex picks up
            # multi-line add_view calls (the path/method kwargs live
            # on continuation lines in fixtures wrapped to column
            # limits).
            add_view_line = if line.includes?(".add_view") && python_paren_delta(line) > 0
                              join_until_python_call_closes(lines, line_index, line)
                            else
                              line
                            end
            if av = add_view_line.match(/\.add_view\s*\((.+)\)/)
              args = av[1]
              rn_match = args.match(/route_name\s*=\s*[rf]?['"]([^'"]+)['"]/)
              next if rn_match.nil?
              route_name = rn_match[1]
              route_key = {current_base_path, route_name}
              next unless route_map.has_key?(route_key)
              route_path, _ = route_map[route_key]

              methods = extract_methods_from_args(args)
              methods = ["GET"] if methods.empty?

              view_func_name = extract_view_func(args)
              body = ""
              view_def_index : Int32? = nil
              if view_func_name && !view_func_name.empty?
                view_def_index = find_function_def(lines, view_func_name)
                body = extract_function_body(lines, view_def_index) unless view_def_index.nil?
              end

              emit_endpoints(path, line_index, route_path, methods, body, view_def_index,
                definition_base_path: current_base_path, source: content)
            end
          end
        end
      end

      result
    end

    private def extract_static_views(content : String, path : String)
      lines = content.lines
      lines.each_with_index do |line, line_index|
        next unless line.includes?(".add_static_view")

        static_line = if python_paren_delta(line) > 0
                        join_until_python_call_closes(lines, line_index, line)
                      else
                        line
                      end
        call_match = static_line.match(/\.add_static_view\s*\((.+)\)\s*$/m)
        next unless call_match

        args = split_python_arguments(call_match[1])
        name = extract_python_keyword_string(args, "name") || args[0]?.try { |arg| extract_python_string(arg) }
        next if name.nil? || name.empty?

        result << Endpoint.new(static_view_route_path(name), "GET", Details.new(PathInfo.new(path, line_index + 1)))
      end
    end

    # config.add_route("name", "/path") plus keyword variants like
    # name="x", pattern="/y" in either order.
    private def extract_route_declarations(content : String, path : String, route_map : RouteMap, base_path : String)
      content.scan(/\.add_route\s*\((.*?)\)/m) do |m|
        args = m[1]
        name = nil
        pattern = nil

        if name_match = args.match(/\bname\s*=\s*[rf]?['"]([^'"]+)['"]/)
          name = name_match[1]
        end
        if pattern_match = args.match(/\bpattern\s*=\s*[rf]?['"]([^'"]*)['"]/)
          pattern = pattern_match[1]
        end

        if name.nil? || pattern.nil?
          literals = [] of String
          args.scan(/[rf]?['"]([^'"]*)['"]/) do |literal_match|
            literals << literal_match[1]
          end
          name ||= literals[0]?
          pattern ||= literals[1]?
        end

        route_map[{base_path, name}] = {pattern, path} if name && pattern
      end
    end

    # Look up `@view_config(...)` either on a single line or across
    # continuation lines (the decorator call may span multiple lines).
    # Returns {route_name, methods} or nil. `route_name` may be nil
    # when a method-level `@view_config(request_method=...)` relies on
    # a class-level `@view_defaults(route_name=...)`.
    private def match_view_config(lines : Array(String), line_index : Int32) : Tuple(String?, Array(String))?
      stripped = lines[line_index].lstrip
      return unless stripped.starts_with?("@view_config") ||
                    stripped.starts_with?("@pyramid.view.view_config") ||
                    stripped.starts_with?("@pyramid.view_config")

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
      route_name = rn_match ? rn_match[1] : nil

      methods = extract_methods_from_args(decorator)
      methods = ["GET"] if methods.empty?
      {route_name, methods}
    end

    private def class_view_defaults_route_name(lines : Array(String), decorator_index : Int32) : String?
      decorator_indent = lines[decorator_index].size - lines[decorator_index].lstrip.size
      idx = decorator_index - 1

      while idx >= 0
        line = lines[idx]
        unless line.strip.empty?
          indent = line.size - line.lstrip.size
          if indent < decorator_indent
            if line.lstrip.starts_with?("class ")
              return extract_view_defaults_route_name_above_class(lines, idx)
            end
          end
        end
        idx -= 1
      end

      nil
    end

    private def extract_view_defaults_route_name_above_class(lines : Array(String), class_index : Int32) : String?
      idx = class_index - 1
      decorators = [] of String

      while idx >= 0
        line = lines[idx]
        stripped = line.lstrip
        # A blank line ends the decorator block above the class.
        break if stripped.empty?

        decorators.unshift(line)
        # Stop once we reach the start of the `@view_defaults` decorator.
        # The previous loop bailed on the FIRST line above the class when
        # it didn't start with `@` — but a MULTI-LINE
        # `@view_defaults(\n  route_name="x",\n)` puts the closing `)` (a
        # continuation line, not an `@…`) directly above the class, so the
        # whole decorator was skipped and the inherited route_name lost
        # (warehouse: 18 class-based views via multi-line @view_defaults).
        # Collect continuation lines until the `@view_defaults` head.
        break if stripped.starts_with?("@view_defaults") ||
                 stripped.starts_with?("@pyramid.view.view_defaults") ||
                 stripped.starts_with?("@pyramid.view_defaults")
        # Defensive cap so a class with no decorators (no blank-line gap
        # above it) doesn't walk the whole file.
        break if decorators.size > 60
        idx -= 1
      end

      decorator = decorators.join(' ')
      return unless decorator.includes?("view_defaults")

      if route_match = decorator.match(/route_name\s*=\s*[rf]?['"]([^'"]+)['"]/)
        return route_match[1]
      end

      nil
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

    private def split_python_arguments(args : String) : Array(String)
      parts = [] of String
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

    # Memoized per keyword — the keyword set is tiny (`name`) but this
    # runs per argument of every static-view declaration.
    private def keyword_string_regex(keyword : String) : Regex
      @keyword_regex_cache[keyword] ||= /^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m
    end

    private def extract_python_keyword_string(args : Array(String), keyword : String) : String?
      keyword_re = keyword_string_regex(keyword)
      args.each do |arg|
        keyword_match = arg.match(keyword_re)
        next unless keyword_match

        return extract_python_string(keyword_match[1])
      end

      nil
    end

    private def extract_python_string(expression : String) : String?
      string_match = expression.strip.match(/^[rf]?['"]([^'"]*)['"]/)
      string_match ? string_match[1] : nil
    end

    private def static_view_route_path(name : String) : String
      normalized = name.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
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

    # Build endpoint(s) for a route+methods combo. `def_index` is the
    # 0-based line of the handler `def` (when known), used to translate
    # tree-sitter rows into absolute callee call-site lines.
    private def emit_endpoints(path : String, line_index : Int32, route_path : String,
                               methods : Array(String), body : String, def_index : Int32?,
                               *,
                               definition_base_path : String,
                               source : String)
      path_params = extract_path_params(route_path)
      request_params = extract_request_params(body)

      # extract_function_body skips the def line, so body row 0 lives
      # at def_index + 1.
      handler_callees = def_index ? build_callees_from(
        body,
        def_index + 1,
        path,
        definition_base_path: definition_base_path,
        source: source
      ) : [] of Callee

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
        handler_callees.each { |c| endpoint.push_callee(c) }
        result << endpoint
      end
    end

    private def extract_path_params(route_path : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new
      # Pyramid path params: `{name}`, `{name:regex}`, or `*remainder` glob.
      route_path.scan(/\{([A-Za-z_][A-Za-z0-9_]*)(?::[^}]+)?\}|\*([A-Za-z_][A-Za-z0-9_]*)/) do |m|
        name = m[1]? || m[2]?
        next if name.nil? || seen.includes?(name)
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

      ACCESSOR_PATTERNS.each do |param_type, bracket_re, get_re|
        body.scan(bracket_re) do |m|
          record.call(m[1], param_type)
        end
        body.scan(get_re) do |m|
          record.call(m[1], param_type)
        end
      end

      params
    end
  end
end
