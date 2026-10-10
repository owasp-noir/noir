require "../../../miniparsers/python"
require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "./flask_family"

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
    include FlaskFamily
    analyzer_for "python_quart"

    # `@app.websocket("/ws")` is the only attribute outside the
    # standard HTTP-method set that the tree-sitter extractor needs
    # to surface here. The synthesised method stays `GET` so the
    # downstream filter logic (which keys off HTTP methods) keeps
    # working; the analyzer rewrites `protocol` to `"ws"` later.
    WEBSOCKET_ATTRIBUTES = {"websocket" => "GET"}

    # Per-line route-discovery patterns. These interpolate only the
    # PYTHON_VAR_NAME_REGEX/DOT_NATION constants, so an inline literal
    # inside the per-line analyze loop recompiled an identical PCRE2
    # pattern on every source line of every file. Compile once here; the
    # `.to_s` expansion of the interpolated constants is byte-identical
    # to the previous inline form, so matching behaviour is unchanged.
    QUART_INSTANCE_RE       = /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:quart\.)?Quart\(/
    VIEW_ASSIGN_RE          = /(#{PYTHON_VAR_NAME_REGEX})=(#{PYTHON_VAR_NAME_REGEX})\.as_view\(/
    ADD_URL_RULE_SCAN_RE    = /(#{PYTHON_VAR_NAME_REGEX})\.add_url_rule\s*\((.*)\)\s*$/m
    REGISTER_BLUEPRINT_RE   = /(#{PYTHON_VAR_NAME_REGEX})\.register_blueprint\((#{DOT_NATION})/
    METHOD_VIEW_DIRECT_RE   = /view_func\s*=\s*(#{PYTHON_VAR_NAME_REGEX})\.as_view\s*\(/
    METHOD_VIEW_VAR_RE      = /view_func\s*=\s*(#{PYTHON_VAR_NAME_REGEX})/
    METHOD_VIEW_POS_VIEW_RE = /^\s*[rf]?['"][^'"]*['"]\s*,\s*[rf]?['"][^'"]*['"]\s*,\s*(#{PYTHON_VAR_NAME_REGEX})\.as_view\s*\(/
    METHOD_VIEW_POS_VAR_RE  = /^\s*[rf]?['"][^'"]*['"]\s*,\s*[rf]?['"][^'"]*['"]\s*,\s*(#{PYTHON_VAR_NAME_REGEX})(?:\s*,|\s*$)/

    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, Bool))).new
    @method_view_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, Array(::String)))).new
    @function_view_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, Array(::String)))).new

    def analyze
      quart_instances = Hash(::String, ::String).new
      quart_instances["app"] ||= "" # Common Quart instance name
      blueprint_prefixes = Hash(::String, ::String).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new
      register_blueprint = Hash(::String, Hash(::String, Array(::String))).new
      blueprint_mounts = Hash(::String, Array(Tuple(::String, ::String, ::String?))).new

      python_files = python_source_files
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          @logger.debug "Analyzing #{path}"

          file_content = fetch_file_content(path)
          next unless file_content.includes?("quart")
          lines = fetch_file_lines(path)

          api_instances = Hash(::String, ::String).new
          path_api_instances[path] = api_instances
          import_map_cache : Hash(::String, Tuple(::String, Int32))? = nil
          view_assignments = Hash(::String, ::String).new

          # Tree-sitter pre-pass: one parse yields decorations + blueprints
          # (previously two full parses of the same buffer).
          ts_decorations, ts_blueprints = Noir::TreeSitterPythonRouteExtractor.extract_decorations_and_blueprints(
            file_content, ["quart"], nil, WEBSOCKET_ATTRIBUTES
          )
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

          ts_blueprints.each do |bp|
            blueprint_prefixes[bp.name] ||= bp.prefix
            api_instances[bp.name] ||= bp.prefix
          end

          lines.each_with_index do |original_line, line_index|
            line = original_line.gsub(" ", "")

            # Identify Quart instance assignments: `app = Quart(__name__)`
            quart_match = line.match QUART_INSTANCE_RE
            if quart_match
              quart_instance_name = quart_match[1]
              api_instances[quart_instance_name] ||= ""
              quart_instances[quart_instance_name] ||= ""
            end

            if view_assign_match = line.match(VIEW_ASSIGN_RE)
              view_assignments[view_assign_match[1]] = view_assign_match[2]
            end

            if line.includes?(".add_url_rule(")
              effective_line = python_paren_delta(original_line) > 0 ? join_until_python_call_closes(lines, line_index, original_line) : original_line
              effective_line.scan(ADD_URL_RULE_SCAN_RE) do |rule_match|
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
            register_blueprint_match = line.match REGISTER_BLUEPRINT_RE
            if register_blueprint_match
              parent_name = register_blueprint_match[1]
              blueprint_name = register_blueprint_match[2]
              url_prefix_match = original_line.match /url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/
              blueprint_mount_prefix = url_prefix_match ? url_prefix_match[1] : nil
              blueprint_mounts[path] ||= [] of Tuple(::String, ::String, ::String?)
              blueprint_mounts[path] << {parent_name, blueprint_name, blueprint_mount_prefix}

              if url_prefix_match
                resolved = false
                parser = get_parser(path)
                if parser.@global_variables.has_key?(blueprint_name)
                  gv = parser.@global_variables[blueprint_name]
                  if gv.type == "Blueprint"
                    add_registered_prefix(register_blueprint, gv.path, blueprint_name, url_prefix_match[1])
                    resolved = true
                  end
                end

                unless resolved
                  import_map_cache ||= find_imported_modules(current_base_path, path)
                  if import_map_cache.has_key?(blueprint_name)
                    source_file, _package_type = import_map_cache[blueprint_name]
                    if !source_file.empty? && File.exists?(source_file)
                      add_registered_prefix(register_blueprint, source_file, blueprint_name, url_prefix_match[1])
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
        blueprint_info.each do |blueprint_name, registered_prefixes|
          if path_api_instances.has_key?(path)
            api_instances = path_api_instances[path]
            if api_instances.has_key?(blueprint_name)
              # The registration's url_prefix replaces the blueprint's
              # own one (Quart reuses Flask's sansio Blueprint).
              api_instances[blueprint_name] = registered_prefixes.first
            end
          end
        end
      end
      apply_nested_blueprint_prefixes(path_api_instances, own_api_instances, blueprint_mounts, register_blueprint)

      # Iterate through the collected route decorations and extract endpoints
      @routes.each do |router_name, router_info_list|
        router_info_list.each do |router_info|
          line_index, path, route_path, extra_params, is_ws = router_info
          source = fetch_file_content(path)
          lines = fetch_file_lines(path)
          api_instances = path_api_instances[path]?
          prefix = (api_instances && api_instances.has_key?(router_name)) ? api_instances[router_name] : ""
          prefixes = route_prefixes(register_blueprint, path, router_name, prefix)

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
            definition_base_path: python_base_path_for(path),
            source: source,
          )

          if is_ws
            # `@app.websocket("/ws")` always emits a single WS endpoint;
            # methods array is forced to GET upstream so the filter
            # plumbing doesn't drop it. Skip param extraction — Quart
            # WebSocket handlers don't read `request.<field>`.
            prefixes.each do |route_prefix|
              route_url = "#{route_prefix}#{route_path}"
              route_url = "/#{route_url}" unless route_url.starts_with?("/")
              details = Details.new(PathInfo.new(path, line_index + 1))
              endpoint = Endpoint.new(route_url.gsub("//", "/"), "GET", details)
              endpoint.protocol = "ws"
              handler_callees.each { |c| endpoint.push_callee(c) }
              result << endpoint
            end
            next
          end

          default_method = HTTP_METHODS.find { |http_method| function_name.downcase == http_method.downcase } || "GET"
          prefixes.flat_map { |p| get_endpoints(default_method, route_path, extra_params, codeblock_lines, p) }.each do |route_endpoint|
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
          lines = fetch_file_lines(path)
          api_instances = path_api_instances[path]?
          prefix = (api_instances && api_instances.has_key?(router_name)) ? api_instances[router_name] : ""
          prefixes = route_prefixes(register_blueprint, path, router_name, prefix)

          function_path = path
          function_source = source
          function_lines = lines
          function_def_index = function_name.includes?(".") ? nil : find_function_def(lines, function_name)
          unless function_def_index
            import_modules = find_imported_modules(python_base_path_for(path), path, source)
            resolved = resolve_external_handler(function_name, path, import_modules)
            next unless resolved

            function_path, resolved_name = resolved
            next unless File.exists?(function_path)

            function_source = fetch_file_content(function_path)
            function_lines = fetch_file_lines(function_path)
            function_def_index = find_function_def(function_lines, resolved_name)
            next unless function_def_index
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
            definition_base_path: python_base_path_for(function_path),
            source: function_source,
          )

          prefixes.flat_map { |p| get_endpoints(route_methods.first, route_path, extra_params, codeblock_lines, p) }.each do |route_endpoint|
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
          lines = fetch_file_lines(path)
          api_instances = path_api_instances[path]?
          prefix = (api_instances && api_instances.has_key?(router_name)) ? api_instances[router_name] : ""
          prefixes = route_prefixes(register_blueprint, path, router_name, prefix)

          class_def_index = find_python_class_def(lines, class_name)
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
              definition_base_path: python_base_path_for(path),
              source: source,
            )

            prefixes.flat_map { |p| get_endpoints(http_method, route_path, extra_params, codeblock_lines, p) }.each do |route_endpoint|
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
      if direct_match = args.match(METHOD_VIEW_DIRECT_RE)
        return direct_match[1]
      end

      if variable_match = args.match(METHOD_VIEW_VAR_RE)
        return view_assignments[variable_match[1]]? || ""
      end

      if positional_match = args.match(METHOD_VIEW_POS_VIEW_RE)
        return positional_match[1]
      end

      if positional_variable_match = args.match(METHOD_VIEW_POS_VAR_RE)
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

    # Scans a handler body for `request.<field>` access patterns and
    # `data = await request.get_json()` / `data = request.json`
    # assignments, then emits a `Param` per discovered key. The
    # `await` keyword is invisible to the access shape so the same
    # regexes work for sync Flask and async Quart.
    private def extract_request_params(codeblock_lines : Array(::String)) : Array(Param)
      codeblock_lines = fold_python_continuations(codeblock_lines)
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
          if matches.empty?
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
          if matches.empty?
            matches = codeblock_line.scan(get_json_re)
          end
          next if matches.empty?

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            params << Param.new(parameter_match[1], "", "json")
          end
          break
        end
      end

      params
    end
  end
end
