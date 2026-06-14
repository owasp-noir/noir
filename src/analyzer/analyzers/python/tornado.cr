require "../../engines/python_engine"

module Analyzer::Python
  class Tornado < PythonEngine
    # Reference: https://tornadoweb.org/en/stable/web.html
    # Reference: https://tornadoweb.org/en/stable/httputil.html#tornado.httputil.HTTPServerRequest
    REQUEST_PARAM_FIELDS = {
      "arguments"      => {["GET"], "query"},
      "body_arguments" => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"          => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "body"           => {["POST", "PUT", "PATCH", "DELETE"], "body"},
      "headers"        => {nil, "header"},
      "cookies"        => {nil, "cookie"},
    }

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "body"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    CLASS_DEF_REGEX = /^class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[\(:]/

    # Per-line matchers that interpolate only constants — hoisted so the
    # analyze loop doesn't recompile identical PCRE2 patterns on every
    # source line. The `.to_s` expansion is byte-identical to the inline
    # literals, so matching behaviour is unchanged.
    APP_INSTANCE_RE = /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:tornado\.web\.)?Application\(/
    HANDLER_LIST_RE = /^(#{PYTHON_VAR_NAME_REGEX})(?::#{DOT_NATION})?=\[/

    @file_content_cache = Hash(::String, ::String).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String))).new
    @import_modules_cache = Hash(::String, Hash(::String, Tuple(::String, Int32))).new

    def analyze
      tornado_app_instances = Hash(::String, ::String).new
      tornado_app_instances["app"] ||= "" # Common tornado app instance name
      path_api_instances = Hash(::String, Hash(::String, ::String)).new

      # Iterate through all Python files in all base paths. Pulls from
      # the detector-built file_map so subtree pruning and --exclude-path
      # apply to this pass too.
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            lines = file.each_line.to_a
            next unless lines.any?(&.includes?("tornado"))
            api_instances = Hash(::String, ::String).new
            path_api_instances[path] = api_instances

            # Tornado's own source documents routing with
            # `.. code-block:: python` examples inside module/class
            # docstrings — routing.py literally shows
            # `Application([(r"/app1/handler", Handler)])`. Those are not
            # real routes. Flag every line that begins inside a
            # triple-quoted string so the route-detection entry points
            # below skip them.
            docstring_line = compute_docstring_line_flags(lines)

            lines.each_with_index do |line, line_index|
              next if docstring_line[line_index]
              line = line.gsub(" ", "") # remove spaces for easier regex matching

              # Identify Tornado Application instance assignments
              app_match = line.includes?("Application(") ? line.match(APP_INSTANCE_RE) : nil
              if app_match
                app_instance_name = app_match[1]
                api_instances[app_instance_name] ||= ""
                tornado_app_instances[app_instance_name] ||= ""
              end

              # Look for URL routing patterns in tornado.web.Application
              # Pattern: [(r"/path", HandlerClass), ...]
              if line.includes?("Application(") || line.includes?("Application([")
                # Extract URL patterns from this and following lines
                extract_url_patterns_from_application(lines, line_index, path, api_instances)
              end

              # Tornado apps commonly attach routes after Application()
              # construction via app.add_handlers(host_pattern, handlers).
              if line.includes?(".add_handlers(")
                extract_url_patterns_from_add_handlers(lines, line_index, path)
              end

              # Module-level handler lists registered from ELSEWHERE.
              # Large Tornado apps (jupyterhub, jupyter-server, the
              # tornado demos) define routes as a top-level
              # `default_handlers = [(r"/api/x", XHandler), ...]` /
              # `handlers = [...]` / `url_patterns = [...]` and aggregate
              # the list in a different module, so there's no local
              # `Application(...)` to anchor on — the entire API was
              # missed (jupyterhub: 66 handler tuples → 0). Detect the
              # assignment by its conventional name and extract its
              # tuples directly; the handler-class gate in
              # `extract_routes_from_lines` keeps non-route lists out.
              list_match = line.includes?("=[") ? line.match(HANDLER_LIST_RE) : nil
              if list_match && tornado_handler_list_name?(list_match[1])
                extract_routes_from_lines(lines, line_index, path)
              end
            end
          end
        end
      end

      result = [] of Endpoint

      # Process route handlers
      path_api_instances.each do |path, _|
        @routes[path]?.try &.each do |route_info|
          line_index, _, route_path, handler_class = route_info
          endpoints = extract_endpoints_from_handler(path, route_path, handler_class)
          endpoints.each do |endpoint|
            details = Details.new(PathInfo.new(path, line_index + 1))
            endpoint.details = details
            result << endpoint
          end
        end
      end

      result
    end

    # For each line, whether its first character sits inside a
    # triple-quoted string (i.e. a docstring opened on an earlier line).
    # A single linear scan tracks the open/close `"""`/`'''` delimiters at
    # file scope; single-line strings and `#` comments are skipped so a
    # stray `"""` inside them doesn't flip the state.
    private def compute_docstring_line_flags(lines : Array(::String)) : Array(Bool)
      flags = Array(Bool).new(lines.size, false)
      in_triple = false
      triple_char = '\0'
      lines.each_with_index do |line, idx|
        flags[idx] = in_triple
        i = 0
        size = line.size
        while i < size
          c = line[i]
          if in_triple
            if c == triple_char && i + 2 < size && line[i + 1] == triple_char && line[i + 2] == triple_char
              in_triple = false
              i += 3
              next
            end
            i += 1
          elsif c == '#'
            break # comment runs to end of line
          elsif c == '"' || c == '\''
            if i + 2 < size && line[i + 1] == c && line[i + 2] == c
              in_triple = true
              triple_char = c
              i += 3
              next
            end
            # Single-line string: skip to its (unescaped) closing quote.
            i += 1
            while i < size
              break if line[i] == c && line[i - 1] != '\\'
              i += 1
            end
            i += 1
          else
            i += 1
          end
        end
      end
      flags
    end

    private def join_multiline_call(lines : Array(::String), start_index : Int32) : ::String
      result = ""
      paren_depth = 0
      found_opening = false
      in_string = false
      string_char = '\0'
      in_triple_string = false
      triple_string_char = '\0'
      i = start_index
      while i < lines.size
        line = lines[i].strip
        line_idx = 0
        while line_idx < line.size
          c = line[line_idx]
          if in_triple_string
            if line_idx + 2 < line.size && c == triple_string_char && line[line_idx + 1] == triple_string_char && line[line_idx + 2] == triple_string_char
              in_triple_string = false
              line_idx += 3
              next
            end
            line_idx += 1
            next
          elsif in_string
            if c == string_char && (line_idx == 0 || line[line_idx - 1] != '\\')
              in_string = false
            end
            line_idx += 1
            next
          elsif c == '#'
            break
          elsif c == '"' || c == '\''
            if line_idx + 2 < line.size && line[line_idx + 1] == c && line[line_idx + 2] == c
              in_triple_string = true
              triple_string_char = c
              line_idx += 3
              next
            else
              in_string = true
              string_char = c
            end
          elsif c == '('
            paren_depth += 1
            found_opening = true
          elsif c == ')'
            paren_depth -= 1
          end
          line_idx += 1
        end
        in_string = false
        result += " " unless result.empty?
        result += line
        break if found_opening && paren_depth <= 0
        i += 1
      end
      result
    end

    private def extract_url_patterns_from_application(lines : Array(::String), start_index : Int32, file_path : ::String, api_instances : Hash(::String, ::String))
      @routes[file_path] ||= [] of Tuple(Int32, ::String, ::String, ::String)

      app_line = join_multiline_call(lines, start_index)

      # Check if Application() is called with a variable name (not an inline list)
      # e.g. Application(routes), Application(handlers=routes), Application(debug=True, handlers=routes)
      var_match = app_line.match(/Application\s*\(.*handlers\s*=\s*(#{PYTHON_VAR_NAME_REGEX})/) ||
                  app_line.match(/Application\s*\(\s*(#{PYTHON_VAR_NAME_REGEX})\s*[,)]/)
      if var_match
        var_name = var_match[1]
        # Find the variable definition in the file
        extract_routes_from_variable(lines, var_name, file_path)
        return
      end

      # Inline list: Application([(...), ...])
      extract_routes_from_lines(lines, start_index, file_path)
    end

    private def extract_url_patterns_from_add_handlers(lines : Array(::String), start_index : Int32, file_path : ::String)
      @routes[file_path] ||= [] of Tuple(Int32, ::String, ::String, ::String)

      app_line = join_multiline_call(lines, start_index)
      if var_match = app_line.match(/\.add_handlers\s*\([^,]+,\s*(#{PYTHON_VAR_NAME_REGEX})\s*[,)]/)
        extract_routes_from_variable(lines, var_match[1], file_path)
        return
      end

      register_routes_from_text(app_line, start_index, file_path)
    end

    private def extract_routes_from_variable(lines : Array(::String), var_name : ::String, file_path : ::String)
      lines.each_with_index do |line, line_index|
        stripped = line.strip
        # `var_name` is the discovered handler-list name (can't be hoisted);
        # it must appear at the start of the line, so skip the regex builds
        # on lines that don't begin with it.
        next unless stripped.starts_with?(var_name)
        # Match: var_name = [ (same line) or var_name = (opening bracket on next line)
        if stripped.match(/^#{var_name}(?::.*?)?\s*=\s*\[/)
          extract_routes_from_lines(lines, line_index, file_path)
          return
        elsif stripped.match(/^#{var_name}(?::.*?)?\s*=\s*$/)
          extract_routes_from_lines(lines, line_index + 1, file_path)
          return
        end
      end
    end

    private def extract_routes_from_lines(lines : Array(::String), start_index : Int32, file_path : ::String)
      # Ensure the route bucket exists. Application/add_handlers callers
      # initialise it themselves, but the module-level handler-list pass
      # calls in here directly — without this guard `@routes[file_path]
      # << …` raised "Missing hash key" and aborted the whole analyzer.
      @routes[file_path] ||= [] of Tuple(Int32, ::String, ::String, ::String)

      # Two-pass on the URLPatterns block:
      #   1. The legacy per-line scan below handles single-line
      #      `(r"/x", Handler)` tuples and the "handler on next
      #      line" variant.
      #   2. After tracking bracket depth identifies the block's
      #      end, run a second scan on the joined block text so
      #      fully wrapped tuples (`(\n  r"/x",\n  Handler,\n)`)
      #      that the per-line regex skipped still surface. New
      #      entries are deduplicated by `(route_path, handler)`
      #      against the existing per-line results.
      block_pieces = [] of ::String

      bracket_depth = 0
      found_opening = false
      in_string = false
      string_char = '\0'
      in_triple_string = false
      triple_string_char = '\0'
      i = start_index
      while i < lines.size
        line = lines[i].strip
        block_pieces << line

        # Track bracket depth, skipping characters inside string literals and comments
        in_comment = false
        line_index = 0
        while line_index < line.size
          c = line[line_index]

          if in_comment
            line_index += 1
            next
          elsif in_triple_string
            if line_index + 2 < line.size && c == triple_string_char && line[line_index + 1] == triple_string_char && line[line_index + 2] == triple_string_char
              in_triple_string = false
              line_index += 3
              next
            end
            line_index += 1
            next
          elsif in_string
            if c == string_char && (line_index == 0 || line[line_index - 1] != '\\')
              in_string = false
            end
            line_index += 1
            next
          else
            if c == '#'
              in_comment = true
            elsif c == '"' || c == '\''
              if line_index + 2 < line.size && line[line_index + 1] == c && line[line_index + 2] == c
                in_triple_string = true
                triple_string_char = c
                line_index += 3
                next
              else
                in_string = true
                string_char = c
              end
            elsif c == '['
              bracket_depth += 1
              found_opening = true
            elsif c == ']'
              bracket_depth -= 1
            end
          end
          line_index += 1
        end

        # Regular strings don't span lines; triple-quoted strings do
        in_string = false

        # Match URL pattern: (r"/path", HandlerClass)
        pattern_match = line.match /\(\s*r?(["'])(.*?)\1\s*,\s*([^),]+)/
        if pattern_match
          route_path = pattern_match[2]
          handler_class = pattern_match[3].strip
          # Gate on the 2nd element looking like a RequestHandler class.
          # Without this, `self.log.debug("Writing PID %i to %s", pid)`
          # and similar `("format string", lowercase_arg)` calls were
          # mistaken for route tuples and surfaced as phantom GET
          # endpoints (jupyterhub app.py log messages).
          @routes[file_path] << {i, "ALL", route_path, handler_class} if tornado_handler_ref?(handler_class)
        elsif partial_match = line.match(/\(\s*r?(["'])(.*?)\1\s*,\s*$/)
          # Route tuple split across lines — handler on next line
          j = i + 1
          while j < lines.size && lines[j].strip.empty?
            j += 1
          end
          if j < lines.size
            handler_match = lines[j].strip.match(/^([a-zA-Z_][a-zA-Z0-9_.]*)/)
            if handler_match && tornado_handler_ref?(handler_match[1].strip)
              @routes[file_path] << {i, "ALL", partial_match[2], handler_match[1].strip}
            end
          end
        end

        # Stop when bracket depth returns to 0 (end of the list)
        break if found_opening && bracket_depth <= 0
        i += 1
      end

      # Second pass: scan the joined block for tuples whose `(` and
      # path/handler sit on different lines. The per-line scan above
      # only catches single-line and "handler on next line" shapes.
      register_routes_from_text(block_pieces.join(" "), start_index, file_path)
    end

    private def register_routes_from_text(block_text : ::String, start_index : Int32, file_path : ::String)
      existing_routes = (@routes[file_path]? || [] of Tuple(Int32, ::String, ::String, ::String))
        .map { |info| {info[2], info[3]} }
        .to_set
      block_text.scan(/\(\s*r?["']([^"']*)["']\s*,\s*([a-zA-Z_][a-zA-Z0-9_.]*)/) do |match|
        next unless match.size >= 3
        route_path = match[1]
        handler_class = match[2]
        next unless tornado_handler_ref?(handler_class)
        next if existing_routes.includes?({route_path, handler_class})
        @routes[file_path] << {start_index, "ALL", route_path, handler_class}
        existing_routes << {route_path, handler_class}
      end

      block_text.scan(/(?:^|[^a-zA-Z0-9_.])(?:tornado\.web\.)?(?:url|URLSpec)\s*\(\s*r?["']([^"']*)["']\s*,\s*([a-zA-Z_][a-zA-Z0-9_.]*)/) do |match|
        next unless match.size >= 3
        route_path = match[1]
        handler_class = match[2]
        next unless tornado_handler_ref?(handler_class)
        next if existing_routes.includes?({route_path, handler_class})
        @routes[file_path] << {start_index, "ALL", route_path, handler_class}
        existing_routes << {route_path, handler_class}
      end
    end

    # Whether `handler` looks like a Tornado RequestHandler class
    # reference (the 2nd element of a `(pattern, handler)` route tuple).
    # Tornado handlers are CamelCase classes — possibly dotted
    # (`web.RequestHandler`, `handlers.ApiHandler`) — so the final
    # segment must start with an uppercase letter. This rejects the
    # lowercase args / format strings that `("...", x)` shaped non-route
    # calls (logging, config tuples) would otherwise smuggle in.
    private def tornado_handler_ref?(handler : ::String) : Bool
      last = handler.split(".").last
      return false if last.empty?
      first = last[0]
      first.ascii_uppercase?
    end

    # Conventional names for a module-level Tornado handler list that is
    # registered from another module (no local `Application(...)`).
    private def tornado_handler_list_name?(name : ::String) : Bool
      n = name.downcase
      n.ends_with?("handlers") || n.ends_with?("routes") ||
        n.ends_with?("urls") || n.ends_with?("url_patterns") ||
        n.ends_with?("urlpatterns") || n == "patterns"
    end

    private def extract_endpoints_from_handler(file_path : ::String, route_path : ::String, handler_class : ::String) : Array(Endpoint)
      endpoints = [] of Endpoint

      # First try to find the handler class in the application file
      found = extract_endpoints_from_class_in_file(file_path, route_path, handler_class, endpoints)

      # If not found locally, resolve imports
      unless found
        import_map = resolve_imports(file_path)
        if import_map.has_key?(handler_class)
          resolved_path, _ = import_map[handler_class]
          if File.exists?(resolved_path)
            extract_endpoints_from_class_in_file(resolved_path, route_path, handler_class, endpoints)
          end
        elsif handler_class.includes?(".")
          parts = handler_class.split(".")
          class_name = parts.last
          module_parts = parts[0...-1]
          resolved = false

          # Try full module path first (e.g., "foo.bar" for foo.bar.Handler)
          module_name = module_parts.join(".")
          if import_map.has_key?(module_name)
            resolved_path, _ = import_map[module_name]
            if File.exists?(resolved_path)
              resolved = extract_endpoints_from_class_in_file(resolved_path, route_path, class_name, endpoints)
            end
          end

          # Fall back to individual module parts (e.g., "handlers" for handlers.ApiHandler)
          unless resolved
            module_parts.each do |name|
              if import_map.has_key?(name)
                resolved_path, _ = import_map[name]
                if File.exists?(resolved_path)
                  if extract_endpoints_from_class_in_file(resolved_path, route_path, class_name, endpoints)
                    break
                  end
                end
              end
            end
          end
        end
      end

      # Only fall back to default GET if handler was not found anywhere
      if endpoints.empty?
        endpoint = Endpoint.new(route_path, "GET")
        endpoints << endpoint
      end

      endpoints
    end

    private def extract_endpoints_from_class_in_file(file_path : ::String, route_path : ::String, handler_class : ::String, endpoints : Array(Endpoint)) : Bool
      lines = read_file_lines(file_path)

      class_found = false
      class_is_websocket = false
      class_indent = 0
      lines.each_with_index do |line, line_index|
        stripped = line.strip
        if (m = stripped.match(CLASS_DEF_REGEX)) && m[1] == handler_class && !class_found
          class_found = true
          class_is_websocket = stripped.includes?("WebSocketHandler")
          class_indent = indent_level(line)
          next
        end

        next unless class_found

        if class_is_websocket &&
           (stripped.starts_with?("def open(") || stripped.starts_with?("async def open("))
          params = extract_path_params_from_method_signature(stripped, route_path)
          extract_params_from_method(lines, line_index, file_path).each do |param|
            add_unique_param(params, param)
          end
          endpoint = Endpoint.new(route_path, "GET", params)
          endpoint.protocol = "ws"

          if codeblock = parse_code_block(lines[line_index..])
            push_callees_from(
              endpoint,
              codeblock,
              line_index,
              file_path,
              definition_base_path: base_path_for(file_path),
              source: read_file_content(file_path),
            )
          end

          endpoints << endpoint
        end

        # Look for HTTP method handlers (both sync and async)
        HTTP_METHODS.each do |http_method|
          if stripped.starts_with?("def #{http_method}(") || stripped.starts_with?("async def #{http_method}(")
            params = extract_path_params_from_method_signature(stripped, route_path)
            extract_params_from_method(lines, line_index, file_path).each do |param|
              add_unique_param(params, param)
            end
            endpoint = Endpoint.new(route_path, http_method.upcase, params)

            # Attach 1-hop callees from this method's body. Each
            # handler method (`def get` / `async def post` / ...) maps
            # to its own endpoint, so the codeblock is per-method —
            # callee scope stays correctly bound to the HTTP verb.
            # `parse_code_block(lines[line_index..])` keeps the def
            # line, so `body_start_line = line_index` matches the
            # helper's contract.
            if codeblock = parse_code_block(lines[line_index..])
              push_callees_from(
                endpoint,
                codeblock,
                line_index,
                file_path,
                definition_base_path: base_path_for(file_path),
                source: read_file_content(file_path),
              )
            end

            endpoints << endpoint
          end
        end

        # Stop when we reach another class at same or lesser indentation (not inner classes)
        if stripped.match(CLASS_DEF_REGEX) && indent_level(line) <= class_indent
          break
        end
      end

      class_found
    end

    private def extract_path_params_from_method_signature(def_line : ::String, route_path : ::String) : Array(Param)
      params = [] of Param

      route_path.scan(/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/) do |match|
        add_unique_param(params, Param.new(match[1], "", "path"))
      end

      route_path.scan(/\(\?P<([a-zA-Z_][a-zA-Z0-9_]*)>/) do |match|
        add_unique_param(params, Param.new(match[1], "", "path"))
      end
      return params unless params.empty?

      capture_count = unnamed_regex_capture_count(route_path)
      return params if capture_count == 0

      method_arg_names(def_line).first(capture_count).each do |name|
        add_unique_param(params, Param.new(name, "", "path"))
      end

      params
    end

    private def method_arg_names(def_line : ::String) : Array(::String)
      match = def_line.match(/def\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(([^)]*)\)/)
      return [] of ::String unless match

      names = [] of ::String
      match[1].split(",").each do |arg|
        name = arg.strip.split("=", 2)[0].split(":", 2)[0].strip
        while name.starts_with?("*")
          name = name.lchop("*")
        end
        next if name.empty? || name.in?(%w[self cls args kwargs])
        names << name
      end
      names
    end

    private def unnamed_regex_capture_count(route_path : ::String) : Int32
      count = 0
      route_path.scan(/(?:^|[^\\])\((?!\?)/) do
        count += 1
      end
      count
    end

    private def add_unique_param(params : Array(Param), param : Param)
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    private def resolve_imports(file_path : ::String) : Hash(::String, Tuple(::String, Int32))
      @import_modules_cache[file_path] ||= begin
        content = read_file_content(file_path)
        find_imported_modules(base_path_for(file_path), file_path, content)
      end
    end

    # Pick the base path that owns this file so the engine's definition
    # resolver can locate imported modules relative to the right root.
    private def base_path_for(file_path : ::String) : ::String
      python_base_path_for(file_path)
    end

    private def read_file_lines(file_path : ::String) : Array(::String)
      content = read_file_content(file_path)
      content.split("\n")
    end

    private def read_file_content(file_path : ::String) : ::String
      return @file_content_cache[file_path] if @file_content_cache.has_key?(file_path)
      content = begin
        CodeLocator.instance.content_for(file_path) || File.read(file_path, encoding: "utf-8", invalid: :skip)
      rescue e : IO::Error
        @logger.debug "Failed to read file: #{file_path} (#{e.message})"
        ""
      end
      @file_content_cache[file_path] = content
      content
    end

    private def indent_level(line : ::String) : Int32
      line.size - line.lstrip.size
    end

    private def extract_params_from_method(lines : Array(::String), method_line_index : Int32, file_path : ::String) : Array(Param)
      params = [] of Param
      method_indent = indent_level(lines[method_line_index])

      # Parse the method body for parameter extraction patterns
      i = method_line_index + 1
      while i < lines.size
        line = lines[i]
        stripped = line.strip

        # Stop at the next method or class at same or lesser indentation (not nested)
        unless stripped.empty?
          if stripped.starts_with?("def ") || stripped.starts_with?("async def ") || stripped.starts_with?("class ")
            break if indent_level(line) <= method_indent
          end
        end

        # Extract Tornado parameter patterns
        extract_tornado_params(stripped, params)

        i += 1
      end

      params
    end

    private def extract_tornado_params(line : ::String, params : Array(Param))
      # self.get_argument("param_name")
      if match = line.match /self\.get_argument\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "query")
      end

      # self.get_body_argument("param_name")
      if match = line.match /self\.get_body_argument\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "form")
      end

      # self.get_cookie("cookie_name")
      if match = line.match /self\.get_cookie\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "cookie")
      end

      # self.request.headers.get("header_name")
      if match = line.match /self\.request\.headers\.get\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "header")
      end

      # self.get_arguments("param_name") — plural form for multi-value query params
      if match = line.match /self\.get_arguments\(["']([^"']+)["']/
        param_name = match[1]
        params << Param.new(param_name, "", "query")
      end

      # JSON body parsing: tornado.escape.json_decode or json.loads
      if (line.includes?("json_decode") || line.includes?("json.loads")) && line.includes?("self.request.body")
        params << Param.new("body", "", "json")
      end
    end
  end
end
