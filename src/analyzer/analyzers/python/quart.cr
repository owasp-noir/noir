require "../../../miniparsers/python"
require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"

module Analyzer::Python
  # Quart is an ASGI re-implementation of Flask's API. Decorator,
  # Blueprint, and request-object shapes mirror Flask 1:1, so this
  # analyzer leans on the same tree-sitter helpers as the Flask one
  # and adds two Quart-specific pieces:
  #
  #   * `@app.websocket("/ws")` — surfaced as `GET` + `protocol = "ws"`
  #     so the existing endpoint pipeline carries it through unchanged
  #   * `await request.get_json()` / `request.json` body extraction —
  #     the same patterns Flask uses; nothing extra is needed because
  #     parameter extraction reads the function body line-by-line and
  #     the `await` prefix doesn't change the access shape.
  class Quart < PythonEngine
    # Reference: https://quart.palletsprojects.com/en/latest/reference/source/quart.wrappers.request.html
    REQUEST_PARAM_FIELDS = {
      "data"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "args"    => {["GET"], "query"},
      "form"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"   => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "values"  => {["GET", "POST", "PUT", "PATCH", "DELETE"], "query"},
      "json"    => {["POST", "PUT", "PATCH", "DELETE"], "json"},
      "cookies" => {nil, "cookie"},
      "headers" => {nil, "header"},
    }

    # Precompiled per-field access patterns. `extract_request_params`
    # runs once per route; rebuilding these interpolated regexes on
    # every call recompiled PCRE2 patterns (8 fields × 2) per endpoint.
    # Compile once here and reuse. {noir_param_type, bracket_re, get_re}
    REQUEST_PARAM_FIELD_PATTERNS = REQUEST_PARAM_FIELDS.map do |field_name, tuple|
      {
        tuple[1],
        Regex.new("request\\.#{field_name}\\[[rf]?['\"]([^'\"]*)['\"]\\]"),
        Regex.new("request\\.#{field_name}\\.get\\([rf]?['\"]([^'\"]*)['\"]"),
      }
    end

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "json"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    # `@app.websocket("/ws")` is the only attribute outside the
    # standard HTTP-method set that the tree-sitter extractor needs
    # to surface here. The synthesised method stays `GET` so the
    # downstream filter logic (which keys off HTTP methods) keeps
    # working; the analyzer rewrites `protocol` to `"ws"` later.
    WEBSOCKET_ATTRIBUTES = {"websocket" => "GET"}

    @file_content_cache = Hash(::String, ::String).new

    # JSON-variable access patterns interpolate a discovered (dynamic but
    # low-cardinality) identifier, so they can't be hoisted to constants —
    # memoize them per variable name instead.
    @json_param_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    private def json_param_regexes(json_variable_name : ::String) : Tuple(Regex, Regex)
      @json_param_regex_cache[json_variable_name] ||= {
        /[^a-zA-Z_]#{Regex.escape(json_variable_name)}\[[rf]?['"]([^'"]*)['"]\]/,
        /[^a-zA-Z_]#{Regex.escape(json_variable_name)}\.get\([rf]?['"]([^'"]*)['"]/,
      }
    end

    @parsers = Hash(::String, PythonParser).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, Bool))).new
    @method_view_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, Array(::String)))).new
    @function_view_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, Array(::String)))).new

    def analyze
      quart_instances = Hash(::String, ::String).new
      quart_instances["app"] ||= "" # Common Quart instance name
      blueprint_prefixes = Hash(::String, ::String).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new
      register_blueprint = Hash(::String, Hash(::String, ::String)).new
      blueprint_mounts = Hash(::String, Array(Tuple(::String, ::String, ::String))).new

      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          file_content = fetch_file_content(path)
          lines = file_content.lines
          next unless lines.any?(&.includes?("quart"))

          api_instances = Hash(::String, ::String).new
          path_api_instances[path] = api_instances
          import_map_cache : Hash(::String, Tuple(::String, Int32))? = nil
          view_assignments = Hash(::String, ::String).new

          # Tree-sitter pre-pass: harvest every `@<router>.route(...)`,
          # `@<router>.<method>(...)`, and `@<router>.websocket(...)`
          # decorator, plus every `<name> = (quart.)?Blueprint(...)`
          # declaration. One parse per file vs. (lines × patterns) regex
          # work; multi-line decorators come along for free.
          ts_decorations = Noir::TreeSitterPythonRouteExtractor.extract_decorations(file_content, nil, WEBSOCKET_ATTRIBUTES)
          ts_decorations.each do |decoration|
            is_ws = decoration.attribute_name == "websocket"
            methods_literal = decoration.methods.map { |m| "'#{m}'" }.join(",")
            extra_params = "methods=[#{methods_literal}]"
            router_info = Tuple(Int32, ::String, ::String, ::String, Bool).new(
              decoration.decorator_line, path, decoration.path, extra_params, is_ws
            )
            @routes[decoration.router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, Bool)
            @routes[decoration.router_name] << router_info
          end

          Noir::TreeSitterPythonRouteExtractor.extract_blueprints(file_content, ["quart"]).each do |bp|
            blueprint_prefixes[bp.name] ||= bp.prefix
            api_instances[bp.name] ||= bp.prefix
          end

          lines.each_with_index do |original_line, line_index|
            line = original_line.gsub(" ", "")

            # Identify Quart instance assignments: `app = Quart(__name__)`
            quart_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:quart\.)?Quart\(/
            if quart_match
              quart_instance_name = quart_match[1]
              api_instances[quart_instance_name] ||= ""
              quart_instances[quart_instance_name] ||= ""
            end

            if view_assign_match = line.match(/(#{PYTHON_VAR_NAME_REGEX})=(#{PYTHON_VAR_NAME_REGEX})\.as_view\(/)
              view_assignments[view_assign_match[1]] = view_assign_match[2]
            end

            if line.includes?(".add_url_rule(")
              effective_line = python_paren_delta(original_line) > 0 ? join_until_python_call_closes(lines, line_index, original_line) : original_line
              effective_line.scan(/(#{PYTHON_VAR_NAME_REGEX})\.add_url_rule\s*\((.*)\)\s*$/m) do |rule_match|
                next if rule_match.size < 3
                router_name = rule_match[1]
                args = rule_match[2]
                route_path = extract_add_url_rule_path(args)
                next if route_path.empty?

                class_name = extract_method_view_class(args, view_assignments)
                methods = extract_add_url_rule_methods(args)
                if class_name.empty?
                  function_name = extract_add_url_rule_function_name(args)
                  next if function_name.empty?

                  route_info = Tuple(Int32, ::String, ::String, ::String, Array(::String)).new(
                    line_index, path, route_path, function_name, methods
                  )
                  @function_view_routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, Array(::String))
                  @function_view_routes[router_name] << route_info
                else
                  route_info = Tuple(Int32, ::String, ::String, ::String, Array(::String)).new(
                    line_index, path, route_path, class_name, methods
                  )
                  @method_view_routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, Array(::String))
                  @method_view_routes[router_name] << route_info
                end
              end
            end

            # Identify Blueprint registration:
            #   `app.register_blueprint(bp, url_prefix="/api")`
            register_blueprint_match = line.match /(#{PYTHON_VAR_NAME_REGEX})\.register_blueprint\((#{DOT_NATION})/
            if register_blueprint_match
              parent_name = register_blueprint_match[1]
              blueprint_name = register_blueprint_match[2]
              url_prefix_match = original_line.match /url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/
              blueprint_mount_prefix = url_prefix_match ? url_prefix_match[1] : ""
              blueprint_mounts[path] ||= [] of Tuple(::String, ::String, ::String)
              blueprint_mounts[path] << {parent_name, blueprint_name, blueprint_mount_prefix}

              if url_prefix_match
                resolved = false
                parser = get_parser(path)
                if parser.@global_variables.has_key?(blueprint_name)
                  gv = parser.@global_variables[blueprint_name]
                  if gv.type == "Blueprint"
                    register_blueprint[gv.path] ||= Hash(::String, ::String).new
                    register_blueprint[gv.path][blueprint_name] = url_prefix_match[1]
                    resolved = true
                  end
                end

                unless resolved
                  import_map_cache ||= find_imported_modules(current_base_path, path)
                  if import_map_cache.has_key?(blueprint_name)
                    source_file, _package_type = import_map_cache[blueprint_name]
                    if !source_file.empty? && File.exists?(source_file)
                      register_blueprint[source_file] ||= Hash(::String, ::String).new
                      register_blueprint[source_file][blueprint_name] = url_prefix_match[1]
                    end
                  end
                end
              end
            end
          end
        end
      end

      # Resolve url_prefix discovered at register_blueprint sites back to
      # the file that declared the Blueprint.
      own_api_instances = clone_path_api_instances(path_api_instances)
      register_blueprint.each do |path, blueprint_info|
        blueprint_info.each do |blueprint_name, blueprint_prefix|
          if path_api_instances.has_key?(path)
            api_instances = path_api_instances[path]
            if api_instances.has_key?(blueprint_name)
              api_instances[blueprint_name] = File.join(blueprint_prefix, api_instances[blueprint_name])
            end
          end
        end
      end
      apply_nested_blueprint_prefixes(path_api_instances, own_api_instances, blueprint_mounts)

      # Iterate through the collected route decorations and extract endpoints
      @routes.each do |router_name, router_info_list|
        router_info_list.each do |router_info|
          line_index, path, route_path, extra_params, is_ws = router_info
          source = fetch_file_content(path)
          lines = source.lines
          api_instances = path_api_instances[path]?
          prefix = (api_instances && api_instances.has_key?(router_name)) ? api_instances[router_name] : ""

          class_def_index = Noir::PythonRouteExtractor.find_def_line(lines, line_index, :down)
          next if class_def_index >= lines.size
          next unless lines[class_def_index].lstrip.starts_with?("def ") ||
                      lines[class_def_index].lstrip.starts_with?("async def ")

          def_match = lines[class_def_index].match /(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
          next unless def_match
          function_name = def_match[3]

          codeblock = parse_code_block(lines[class_def_index..])
          next if codeblock.nil?
          codeblock_lines = codeblock.split("\n")

          handler_callees = build_callees_from(
            codeblock,
            class_def_index,
            path,
            definition_base_path: base_path_for(path),
            source: source,
          )

          if is_ws
            # `@app.websocket("/ws")` always emits a single WS endpoint;
            # methods array is forced to GET upstream so the filter
            # plumbing doesn't drop it. Skip param extraction — Quart
            # WebSocket handlers don't read `request.<field>`.
            route_url = "#{prefix}#{route_path}"
            route_url = "/#{route_url}" unless route_url.starts_with?("/")
            details = Details.new(PathInfo.new(path, line_index + 1))
            endpoint = Endpoint.new(route_url.gsub("//", "/"), "GET", details)
            endpoint.protocol = "ws"
            handler_callees.each { |c| endpoint.push_callee(c) }
            result << endpoint
            next
          end

          default_method = HTTP_METHODS.find { |http_method| function_name.downcase == http_method.downcase } || "GET"
          get_endpoints(default_method, route_path, extra_params, codeblock_lines, prefix).each do |route_endpoint|
            route_endpoint.details = Details.new(PathInfo.new(path, line_index + 1))
            handler_callees.each { |c| route_endpoint.push_callee(c) }
            result << route_endpoint
          end
        end
      end

      @function_view_routes.each do |router_name, route_infos|
        route_infos.each do |route_info|
          line_index, path, route_path, function_name, methods = route_info
          source = fetch_file_content(path)
          lines = source.lines
          api_instances = path_api_instances[path]?
          prefix = (api_instances && api_instances.has_key?(router_name)) ? api_instances[router_name] : ""

          function_path = path
          function_source = source
          function_lines = lines
          function_def_index = function_name.includes?(".") ? -1 : find_function_def(lines, function_name)
          if function_def_index < 0
            import_modules = find_imported_modules(base_path_for(path), path, source)
            resolved = resolve_external_function_view(function_name, path, import_modules)
            next unless resolved

            function_path, resolved_name = resolved
            next unless File.exists?(function_path)

            function_source = fetch_file_content(function_path)
            function_lines = function_source.lines
            function_def_index = find_function_def(function_lines, resolved_name)
            next if function_def_index < 0
          end

          codeblock = parse_code_block(function_lines[function_def_index..])
          next if codeblock.nil?
          codeblock_lines = codeblock.split("\n")
          route_methods = methods.empty? ? ["GET"] : methods
          extra_params = "methods=[#{route_methods.map { |m| "'#{m.upcase}'" }.join(",")}]"

          handler_callees = build_callees_from(
            codeblock,
            function_def_index,
            function_path,
            definition_base_path: base_path_for(function_path),
            source: function_source,
          )

          get_endpoints(route_methods.first, route_path, extra_params, codeblock_lines, prefix).each do |route_endpoint|
            route_endpoint.details = Details.new(PathInfo.new(path, line_index + 1))
            handler_callees.each { |c| route_endpoint.push_callee(c) }
            result << route_endpoint
          end
        end
      end

      @method_view_routes.each do |router_name, route_infos|
        route_infos.each do |route_info|
          line_index, path, route_path, class_name, methods = route_info
          source = fetch_file_content(path)
          lines = source.lines
          api_instances = path_api_instances[path]?
          prefix = (api_instances && api_instances.has_key?(router_name)) ? api_instances[router_name] : ""

          class_def_index = find_class_def(lines, class_name)
          next if class_def_index < 0

          class_indent = lines[class_def_index].size - lines[class_def_index].lstrip.size
          route_methods = methods.empty? ? infer_method_view_methods(lines, class_def_index, class_indent) : methods
          route_methods << "GET" if route_methods.empty?

          route_methods.uniq.each do |http_method|
            method_def_index = find_method_def(lines, class_def_index, class_indent, http_method.downcase)
            method_def_index = find_method_def(lines, class_def_index, class_indent, "dispatch_request") if method_def_index < 0
            next if method_def_index < 0

            codeblock = parse_code_block(lines[method_def_index..])
            next if codeblock.nil?
            codeblock_lines = codeblock.split("\n")
            extra_params = "methods=['#{http_method.upcase}']"

            handler_callees = build_callees_from(
              codeblock,
              method_def_index,
              path,
              definition_base_path: base_path_for(path),
              source: source,
            )

            get_endpoints(http_method, route_path, extra_params, codeblock_lines, prefix).each do |route_endpoint|
              route_endpoint.details = Details.new(PathInfo.new(path, line_index + 1))
              handler_callees.each { |c| route_endpoint.push_callee(c) }
              result << route_endpoint
            end
          end
        end
      end

      Fiber.yield
      result
    end

    private def extract_add_url_rule_path(args : ::String) : ::String
      if keyword_match = args.match(/(?:rule|path)\s*=\s*[rf]?['"]([^'"]*)['"]/)
        return keyword_match[1]
      end

      if positional_match = args.match(/^\s*[rf]?['"]([^'"]*)['"]/)
        return positional_match[1]
      end

      ""
    end

    private def extract_method_view_class(args : ::String, view_assignments : Hash(::String, ::String)) : ::String
      if direct_match = args.match(/view_func\s*=\s*(#{PYTHON_VAR_NAME_REGEX})\.as_view\s*\(/)
        return direct_match[1]
      end

      if variable_match = args.match(/view_func\s*=\s*(#{PYTHON_VAR_NAME_REGEX})/)
        return view_assignments[variable_match[1]]? || ""
      end

      if positional_match = args.match(/^\s*[rf]?['"][^'"]*['"]\s*,\s*[rf]?['"][^'"]*['"]\s*,\s*(#{PYTHON_VAR_NAME_REGEX})\.as_view\s*\(/)
        return positional_match[1]
      end

      if positional_variable_match = args.match(/^\s*[rf]?['"][^'"]*['"]\s*,\s*[rf]?['"][^'"]*['"]\s*,\s*(#{PYTHON_VAR_NAME_REGEX})(?:\s*,|\s*$)/)
        return view_assignments[positional_variable_match[1]]? || ""
      end

      ""
    end

    # Constant-only interpolation (DOT_NATION) — hoisted so the per-call
    # sites don't recompile them.
    VIEW_FUNC_KWARG_RE  = /view_func\s*=\s*(#{DOT_NATION})(?:\s*,|\s*\)|\s*$)/
    DOTTED_REFERENCE_RE = /^#{DOT_NATION}$/

    private def extract_add_url_rule_function_name(args : ::String) : ::String
      if view_func_match = args.match(VIEW_FUNC_KWARG_RE)
        return view_func_match[1]
      end

      positional_parts = split_python_call_args(args)
      view_arg = if positional_parts.size >= 3
                   positional_parts[2]
                 elsif positional_parts.size == 2
                   positional_parts[1]
                 else
                   ""
                 end
      view_arg.matches?(DOTTED_REFERENCE_RE) ? view_arg : ""
    end

    private def resolve_external_function_view(function_ref : ::String,
                                               current_path : ::String,
                                               import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String)?
      reference = function_ref.strip
      return if reference.empty?

      if reference.includes?(".")
        receiver, function_name = reference.split(".", 2)
        if import_info = import_modules[receiver]?
          import_path = import_info.first
          return {import_path, function_name} unless import_path.empty?
        end

        sibling_module_path = File.join(File.dirname(current_path), "#{receiver}.py")
        return {sibling_module_path, function_name} if File.exists?(sibling_module_path)

        return
      end

      if import_info = import_modules[reference]?
        import_path = import_info.first
        return {import_path, reference} unless import_path.empty?
      end

      nil
    end

    private def split_python_call_args(args : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      single_quote = false
      double_quote = false
      escaped = false

      args.each_char do |ch|
        if escaped
          current << ch
          escaped = false
          next
        end

        if ch == '\\'
          current << ch
          escaped = true
          next
        end

        if single_quote
          single_quote = false if ch == '\''
          current << ch
          next
        end

        if double_quote
          double_quote = false if ch == '"'
          current << ch
          next
        end

        case ch
        when '\''
          single_quote = true
        when '"'
          double_quote = true
        when '('
          paren_depth += 1
        when ')'
          paren_depth -= 1 if paren_depth > 0
        when '[', '{'
          bracket_depth += 1
        when ']', '}'
          bracket_depth -= 1 if bracket_depth > 0
        when ','
          if paren_depth == 0 && bracket_depth == 0
            part = current.to_s.strip
            parts << part unless part.empty?
            current = String::Builder.new
            next
          end
        end

        current << ch
      end

      part = current.to_s.strip
      parts << part unless part.empty?
      parts
    end

    private def extract_add_url_rule_methods(args : ::String) : Array(::String)
      methods = [] of ::String
      methods_match = args.match(/methods\s*=\s*[\[\(](.*?)[\]\)]/m)
      return methods unless methods_match

      methods_match[1].scan(/['"]([A-Za-z]+)['"]/) do |method_match|
        method = method_match[1].upcase
        methods << method if HTTP_METHODS.any? { |hm| hm.upcase == method }
      end
      methods
    end

    private def find_class_def(lines : Array(::String), class_name : ::String) : Int32
      lines.each_with_index do |line, idx|
        stripped = line.lstrip
        class_prefix = "class #{class_name}"
        if stripped.starts_with?(class_prefix) &&
           (stripped.size == class_prefix.size || stripped[class_prefix.size].in?('(', ':', ' ', '\t'))
          return idx
        end
      end

      -1
    end

    private def infer_method_view_methods(lines : Array(::String), class_def_index : Int32, class_indent : Int32) : Array(::String)
      methods = extract_class_declared_methods(lines, class_def_index, class_indent)
      i = class_def_index + 1
      while i < lines.size
        line = lines[i]
        if class_match = line.match(/(\s*)class\s+/)
          break if class_match[1].size <= class_indent
        end

        if method_match = line.match(/(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/)
          if method_match[1].size > class_indent
            method = HTTP_METHODS.find { |http_method| http_method.downcase == method_match[3].downcase }
            methods << method.upcase if method
          end
        end
        i += 1
      end

      methods
    end

    private def extract_class_declared_methods(lines : Array(::String), class_def_index : Int32, class_indent : Int32) : Array(::String)
      methods = [] of ::String
      i = class_def_index + 1
      while i < lines.size
        line = lines[i]
        stripped = line.strip
        unless stripped.empty?
          indent = line.size - line.lstrip.size
          break if indent <= class_indent

          if stripped.match(/^methods\s*=/)
            declaration = collect_python_collection_assignment(lines, i, line)
            declaration.scan(/['"]([A-Za-z]+)['"]/) do |method_match|
              method = method_match[1].upcase
              methods << method if HTTP_METHODS.any? { |known| known.upcase == method }
            end
            break
          end
        end
        i += 1
      end

      methods.uniq
    end

    private def collect_python_collection_assignment(lines : Array(::String), start_index : Int32, line : ::String) : ::String
      return line unless line.includes?("[") || line.includes?("(")

      pieces = [line]
      depth = python_paren_delta(line) + python_bracket_delta(line)
      i = start_index + 1
      while i < lines.size && depth > 0
        pieces << lines[i]
        depth += python_paren_delta(lines[i]) + python_bracket_delta(lines[i])
        i += 1
      end

      pieces.join(" ")
    end

    private def python_bracket_delta(line : ::String) : Int32
      depth = 0
      in_quote : Char? = nil
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
        when '['
          depth += 1
        when ']'
          depth -= 1
        end
      end

      depth
    end

    private def find_method_def(lines : Array(::String), class_def_index : Int32, class_indent : Int32, method_name : ::String) : Int32
      # Compile once per call; an interpolated literal inside the loop
      # would be recompiled on every line.
      method_def_re = /(\s*)(async\s+)?def\s+#{Regex.escape(method_name)}\s*\(/
      i = class_def_index + 1
      while i < lines.size
        line = lines[i]
        if class_match = line.match(/(\s*)class\s+/)
          break if class_match[1].size <= class_indent
        end

        if method_match = line.match(method_def_re)
          return i if method_match[1].size > class_indent
        end
        i += 1
      end

      -1
    end

    private def find_function_def(lines : Array(::String), function_name : ::String) : Int32
      def_re = /^\s*(?:async\s+)?def\s+#{Regex.escape(function_name)}\s*\(/
      lines.each_with_index do |line, index|
        if line.match(def_re)
          return index
        end
      end

      -1
    end

    private def fetch_file_content(path : ::String) : ::String
      @file_content_cache[path] ||= read_file_content(path)
    end

    private def base_path_for(file_path : ::String) : ::String
      python_base_path_for(file_path)
    end

    private def clone_path_api_instances(path_api_instances : Hash(::String, Hash(::String, ::String))) : Hash(::String, Hash(::String, ::String))
      cloned = Hash(::String, Hash(::String, ::String)).new
      path_api_instances.each do |path, api_instances|
        cloned[path] = api_instances.dup
      end

      cloned
    end

    private def apply_nested_blueprint_prefixes(path_api_instances : Hash(::String, Hash(::String, ::String)),
                                                own_api_instances : Hash(::String, Hash(::String, ::String)),
                                                blueprint_mounts : Hash(::String, Array(Tuple(::String, ::String, ::String))))
      blueprint_mounts.each do |path, mounts|
        api_instances = path_api_instances[path]?
        next unless api_instances

        own_prefixes = own_api_instances[path]? || api_instances
        changed = true
        while changed
          changed = false
          mounts.each do |mount|
            parent_name, child_name, mount_prefix = mount
            next unless api_instances.has_key?(child_name)

            parent_prefix = api_instances[parent_name]? || ""
            child_own_prefix = own_prefixes[child_name]? || ""
            resolved_prefix = File.join(parent_prefix, mount_prefix, child_own_prefix)
            next if api_instances[child_name] == resolved_prefix

            api_instances[child_name] = resolved_prefix
            changed = true
          end
        end
      end
    end

    def create_parser(path : ::String, content : ::String = "") : PythonParser
      content = fetch_file_content(path) if content.empty?
      PythonParser.new(path, content, @parsers, depth: 0)
    end

    def get_parser(path : ::String, content : ::String = "") : PythonParser
      @parsers[path] ||= create_parser(path, content)
      @parsers[path]
    end

    # Build endpoints from a single route decoration. Mirrors the Flask
    # adapter's behaviour: split on declared `methods=[...]`, default to
    # GET, run parameter extraction over the handler body once and
    # filter the params per method.
    def get_endpoints(method : ::String, route_path : ::String, extra_params : ::String,
                      codeblock_lines : Array(::String), prefix : ::String)
      endpoints = [] of Endpoint
      methods = [] of ::String

      if !prefix.ends_with?("/") && !route_path.starts_with?("/")
        prefix = "#{prefix}/"
      end

      methods_match = extra_params.match /methods\s*=\s*(.*)/
      if !methods_match.nil? && methods_match.size == 2
        methods_match[1].scan(/['"]([^'"]*)['"']/) do |m|
          method_name = m[1].upcase
          methods << method_name if HTTP_METHODS.any? { |hm| hm.upcase == method_name }
        end
      end
      methods << method.upcase if methods.empty?

      suspicious_params = extract_request_params(codeblock_lines)

      methods.uniq.each do |http_method_name|
        route_url = "#{prefix}#{route_path}"
        route_url = "/#{route_url}" unless route_url.starts_with?("/")

        params = get_filtered_params(http_method_name, suspicious_params)
        endpoints << Endpoint.new(route_url.gsub("//", "/"), http_method_name, params)
      end

      endpoints
    end

    # Scans a handler body for `request.<field>` access patterns and
    # `data = await request.get_json()` / `data = request.json`
    # assignments, then emits a `Param` per discovered key. The
    # `await` keyword is invisible to the access shape so the same
    # regexes work for sync Flask and async Quart.
    private def extract_request_params(codeblock_lines : Array(::String)) : Array(Param)
      params = [] of Param
      json_variable_names = [] of ::String
      # (json-variable regexes are memoized in @json_param_regex_cache —
      # they interpolate a discovered identifier so they can't be consts.)

      codeblock_lines.each do |codeblock_line|
        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*(?:await\s+)?json\.loads\((?:await\s+)?request\.data/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*(?:await\s+)?request\.(?:get_json\([^)]*\)|json)/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
      end

      codeblock_lines.each do |codeblock_line|
        REQUEST_PARAM_FIELD_PATTERNS.each do |field_pattern|
          noir_param_type, bracket_re, get_re = field_pattern
          matches = codeblock_line.scan(bracket_re)
          if matches.size == 0
            matches = codeblock_line.scan(get_re)
          end

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            params << Param.new(parameter_match[1], "", noir_param_type)
          end
        end

        # JSON dict access on the variables found above. This used to run
        # inside the field-pattern loop (once per missed field — i.e.
        # effectively per field per line), recompiling two interpolated
        # regexes each time and appending the same matches repeatedly;
        # `get_filtered_params` deduplicates by (name, param_type), so
        # scanning once per line is output-identical.
        json_variable_names.each do |json_variable_name|
          bracket_json_re, get_json_re = json_param_regexes(json_variable_name)
          matches = codeblock_line.scan(bracket_json_re)
          if matches.size == 0
            matches = codeblock_line.scan(get_json_re)
          end
          next if matches.size == 0

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            params << Param.new(parameter_match[1], "", "json")
          end
          break
        end
      end

      params
    end

    def get_filtered_params(method : ::String, params : Array(Param)) : Array(Param)
      filtered_params = Array(Param).new
      upper_method = method.upcase

      params.each do |param|
        is_support_param = false
        support_methods = REQUEST_PARAM_TYPES.fetch(param.param_type, nil)
        if !support_methods.nil?
          support_methods.each do |support_method|
            is_support_param = true if upper_method == support_method.upcase
          end
        else
          is_support_param = true
        end

        filtered_params.each do |filtered_param|
          if filtered_param.name == param.name && filtered_param.param_type == param.param_type
            is_support_param = false
            break
          end
        end

        filtered_params << param if is_support_param
      end

      filtered_params
    end
  end
end
