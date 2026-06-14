require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"

module Analyzer::Python
  class Sanic < PythonEngine
    alias ScopedNameKey = Tuple(::String, ::String)

    # Reference: https://sanic.readthedocs.io/en/stable/sanic/request.html
    REQUEST_PARAM_FIELDS = {
      "args"    => {["GET"], "query"},
      "form"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"   => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "json"    => {["POST", "PUT", "PATCH", "DELETE"], "json"},
      "cookies" => {nil, "cookie"},
      "headers" => {nil, "header"},
    }

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "json"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    # Hoisted out of the analyze loops: an interpolated regex literal
    # recompiles (PCRE2 JIT) on every evaluation, and these interpolate
    # only constants. The `.to_s` expansion is byte-identical to the
    # previous inline form, so matching behaviour is unchanged.
    SANIC_INSTANCE_RE           = /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:sanic\.)?Sanic\(/
    STATIC_CALL_RE              = /\b(#{PYTHON_VAR_NAME_REGEX})\.static\s*\((.*)\)\s*$/m
    ADD_ROUTE_CALL_RE           = /\b(#{PYTHON_VAR_NAME_REGEX})\.add_route\s*\((.*)\)\s*$/m
    ADD_WEBSOCKET_ROUTE_CALL_RE = /\b(#{PYTHON_VAR_NAME_REGEX})\.add_websocket_route\s*\((.*)\)\s*$/m
    AS_VIEW_RE                  = /^(#{PYTHON_VAR_NAME_REGEX})\.as_view\s*\(/
    DOTTED_REFERENCE_RE         = /^#{PYTHON_VAR_NAME_REGEX}(?:\.#{PYTHON_VAR_NAME_REGEX})*$/
    BLUEPRINT_CALL_RE           = /\.blueprint\s*\(\s*(#{PYTHON_VAR_NAME_REGEX})(.*?)\)/m

    # `get_endpoints` rebuilt two PCRE2 patterns per request field on
    # every handler-body line. The field set is fixed, so precompile the
    # access patterns (and the `request.<field>` guard substring) once.
    # Tuple shape: {guard_substring, noir_param_type, paren_re, bracket_re}
    REQUEST_PARAM_FIELD_PATTERNS = REQUEST_PARAM_FIELDS.map do |field, tuple|
      {"request.#{field}",
       tuple[1],
       /request\.#{field}(?:\.get)?\(['"']([^'"']+)['"']\)/,
       /request\.#{field}\[['"']([^'"']+)['"']\]/}
    end

    @keyword_regex_cache = Hash(::String, Regex).new
    @json_var_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    @file_content_cache = Hash(::String, ::String).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, ::String))).new
    @programmatic_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, ::String))).new
    @programmatic_websocket_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, ::String))).new
    @programmatic_class_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, ::String))).new
    @static_routes = Hash(::String, Array(Tuple(Int32, ::String, ::String))).new

    def analyze
      sanic_instances = Hash(::String, ::String).new
      sanic_instances["app"] ||= "" # Common sanic instance name
      blueprint_prefixes = Hash(::String, ::String).new
      blueprint_registration_prefixes = Hash(ScopedNameKey, Array(::String)).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new
      # `Blueprint.group(bp1, bp2, url_prefix="/api")` prepends the group
      # url_prefix to each member, and `version=`/`Blueprint(version=)`
      # prepends `/v<n>` outermost (`/v1/sentient/robot/ultron/name`).
      blueprint_group_prefixes = Hash(::String, ::String).new # member bp -> group url_prefix
      blueprint_versions = Hash(::String, ::String).new       # bp -> version

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
            file_content = file.gets_to_end
            lines = file_content.lines
            next unless lines.any?(&.includes?("sanic"))
            api_instances = Hash(::String, ::String).new
            path_api_instances[path] = api_instances

            # Tree-sitter pre-pass: parse once and harvest every
            # `@<router>.route(...)` / `@<router>.<method>(...)` decorator
            # plus every `<name> = (sanic.)?Blueprint(url_prefix=...)`
            # declaration. Replaces the per-line regex sweep in the loop
            # below and handles multi-line decorators for free.
            Noir::TreeSitterPythonRouteExtractor.extract_blueprints(file_content, ["sanic"]).each do |bp|
              blueprint_prefixes[bp.name] ||= bp.prefix
              api_instances[bp.name] ||= bp.prefix
            end
            collect_blueprint_registrations(file_content, blueprint_registration_prefixes, current_base_path)
            collect_blueprint_groups_and_versions(file_content, blueprint_group_prefixes, blueprint_versions)
            Noir::TreeSitterPythonRouteExtractor.extract_decorations(file_content, extra_attributes: {"websocket" => "GET"}).each do |decoration|
              methods_literal = decoration.methods.map { |m| "'#{m}'" }.join(",")
              extra_params = "methods=[#{methods_literal}]"
              router_info = Tuple(Int32, ::String, ::String, ::String, ::String).new(decoration.decorator_line, path, decoration.path, extra_params, decoration.attribute_name)
              @routes[decoration.router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, ::String)
              @routes[decoration.router_name] << router_info
            end

            lines.each_with_index do |original_line, line_index|
              line = original_line.gsub(" ", "") # remove spaces for easier regex matching

              # Identify Sanic instance assignments (tree-sitter extractor
              # doesn't cover this shape yet).
              sanic_match = line.includes?("Sanic(") ? line.match(SANIC_INSTANCE_RE) : nil
              if sanic_match
                sanic_instance_name = sanic_match[1]
                api_instances[sanic_instance_name] ||= ""
                sanic_instances[sanic_instance_name] ||= ""
              end

              if line.includes?(".add_route(")
                effective_line = python_paren_delta(original_line) > 0 ? join_until_python_call_closes(lines, line_index, original_line) : original_line
                if class_route_info = parse_programmatic_class_route(effective_line)
                  router_name, route_path, class_name, extra_params = class_route_info
                  @programmatic_class_routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, ::String)
                  @programmatic_class_routes[router_name] << {line_index, path, route_path, extra_params, class_name}
                elsif route_info = parse_programmatic_route(effective_line)
                  router_name, route_path, handler_name, extra_params = route_info
                  @programmatic_routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, ::String)
                  @programmatic_routes[router_name] << {line_index, path, route_path, extra_params, handler_name}
                end
              end

              if line.includes?(".add_websocket_route(")
                effective_line = python_paren_delta(original_line) > 0 ? join_until_python_call_closes(lines, line_index, original_line) : original_line
                if route_info = parse_programmatic_websocket_route(effective_line)
                  router_name, route_path, handler_name, extra_params = route_info
                  @programmatic_websocket_routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, ::String)
                  @programmatic_websocket_routes[router_name] << {line_index, path, route_path, extra_params, handler_name}
                end
              end

              if line.includes?(".static(")
                effective_line = python_paren_delta(original_line) > 0 ? join_until_python_call_closes(lines, line_index, original_line) : original_line
                if static_route_info = parse_static_route(effective_line)
                  router_name, static_path = static_route_info
                  @static_routes[router_name] ||= [] of Tuple(Int32, ::String, ::String)
                  @static_routes[router_name] << {line_index, path, static_path}
                end
              end
            end
          end
        end
      end

      # Iterate through the routes and extract endpoints
      @routes.each do |router_name, router_info_list|
        router_info_list.each do |router_info|
          line_index, path, route_path, extra_params, route_attr = router_info
          source = fetch_file_content(path)
          lines = source.lines
          definition_base_path = python_base_path_for(path)
          # Route-level `@bp.get("/x", version=2)` overrides the blueprint's
          # version for just this route.
          decorator_stmt = python_paren_delta(lines[line_index]? || "") > 0 ? join_until_python_call_closes(lines, line_index, lines[line_index]) : (lines[line_index]? || "")
          route_version = decorator_stmt.match(/\bversion\s*=\s*['"]?(\w+)['"]?/).try(&.[1])
          expect_params, class_def_index = extract_params_from_decorator(path, lines, line_index)
          api_instances = path_api_instances[path]
          if api_instances.has_key?(router_name)
            prefix = api_instances[router_name]
          else
            prefix = ""
          end
          registration_prefixes = blueprint_registration_prefixes[{definition_base_path, router_name}]? || [""]

          is_class_router = false
          indent = lines[class_def_index].index("def") || 0
          unless lines[class_def_index].lstrip.starts_with?("def ") || lines[class_def_index].lstrip.starts_with?("async def ")
            if lines[class_def_index].lstrip.starts_with?("class ")
              indent = lines[class_def_index].index("class") || 0
              is_class_router = true
            else
              next # Skip if not a function and not a class
            end
          end

          i = class_def_index
          function_name_locations = Array(Tuple(Int32, ::String)).new
          while i < lines.size
            def_match = lines[i].match /(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
            if def_match
              # Stop when the indentation is less than or equal to the class indentation
              break if is_class_router && def_match[1].size <= indent

              # Stop when the first function is found
              function_name_locations << Tuple.new(i, def_match[3])
              break unless is_class_router
            end

            # Stop when the next class definition is found
            if is_class_router && i != class_def_index
              class_match = lines[i].match /(\s*)class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*/
              if class_match
                break if class_match[1].size <= indent
              end
            end

            i += 1
          end

          function_name_locations.each do |_class_def_index, _function_name|
            if is_class_router
              # Replace the class expect params with the function expect params
              def_expect_params, _ = extract_params_from_decorator(path, lines, _class_def_index, :up)
              if def_expect_params.size > 0
                expect_params = def_expect_params
              end
            end

            codeblock = parse_code_block(lines[_class_def_index..])
            next if codeblock.nil?
            codeblock_lines = codeblock.split("\n")

            # Hoisted out of the per-endpoint loop: one route declaration
            # can emit multiple endpoints (e.g. `methods=["POST","PUT"]`),
            # and they all share the same handler body, so parse once.
            handler_callees = build_callees_from(
              codeblock,
              _class_def_index,
              path,
              definition_base_path: definition_base_path,
              source: source
            )

            # Get the HTTP method from the function name when it is not specified in the route decorator
            method = HTTP_METHODS.find { |http_method| _function_name.downcase == http_method.downcase } || "GET"
            registration_prefixes.each do |registration_prefix|
              full_prefix = compose_sanic_prefix(router_name, registration_prefix, prefix, blueprint_group_prefixes, blueprint_versions, route_version)
              get_endpoints(method, route_path, extra_params, codeblock_lines, full_prefix, route_attr).each do |endpoint|
                details = Details.new(PathInfo.new(path, line_index + 1))
                endpoint.details = details

                handler_callees.each { |c| endpoint.push_callee(c) }

                # Add expect params as endpoint params
                expect_params.each do |expect_param|
                  endpoint.push_param(expect_param)
                end

                result << endpoint
              end
            end
          end
        end
      end

      @programmatic_routes.each do |router_name, router_info_list|
        router_info_list.each do |route_info|
          line_index, path, route_path, extra_params, handler_name = route_info
          source = fetch_file_content(path)
          lines = source.lines
          definition_base_path = python_base_path_for(path)
          api_instances = path_api_instances[path]
          prefix = api_instances[router_name]? || ""
          registration_prefixes = blueprint_registration_prefixes[{definition_base_path, router_name}]? || [""]

          function_def_index = find_function_def(lines, handler_name)
          handler_path = path
          handler_source = source
          handler_lines = lines
          function_def_index ||= find_self_method_def(lines, line_index, handler_name)
          if function_def_index.nil?
            import_modules = find_imported_modules(definition_base_path, path, source)
            resolved = resolve_external_handler(handler_name, path, import_modules)
            next unless resolved

            handler_path, function_name = resolved
            next unless File.exists?(handler_path)

            handler_source = fetch_file_content(handler_path)
            handler_lines = handler_source.lines
            function_def_index = find_function_def(handler_lines, function_name)
            next if function_def_index.nil?
          end

          codeblock = parse_code_block(handler_lines[function_def_index..])
          next if codeblock.nil?
          codeblock_lines = codeblock.split("\n")
          handler_callees = build_callees_from(
            codeblock,
            function_def_index,
            handler_path,
            definition_base_path: definition_base_path,
            source: handler_source
          )

          registration_prefixes.each do |registration_prefix|
            full_prefix = compose_sanic_prefix(router_name, registration_prefix, prefix, blueprint_group_prefixes, blueprint_versions)
            get_endpoints("GET", route_path, extra_params, codeblock_lines, full_prefix).each do |endpoint|
              endpoint.details = Details.new(PathInfo.new(path, line_index + 1))
              handler_callees.each { |c| endpoint.push_callee(c) }
              result << endpoint
            end
          end
        end
      end

      @programmatic_websocket_routes.each do |router_name, router_info_list|
        router_info_list.each do |route_info|
          line_index, path, route_path, extra_params, handler_name = route_info
          source = fetch_file_content(path)
          lines = source.lines
          definition_base_path = python_base_path_for(path)
          api_instances = path_api_instances[path]
          prefix = api_instances[router_name]? || ""
          registration_prefixes = blueprint_registration_prefixes[{definition_base_path, router_name}]? || [""]

          function_def_index = find_function_def(lines, handler_name)
          handler_path = path
          handler_source = source
          handler_lines = lines
          function_def_index ||= find_self_method_def(lines, line_index, handler_name)
          if function_def_index.nil?
            import_modules = find_imported_modules(definition_base_path, path, source)
            resolved = resolve_external_handler(handler_name, path, import_modules)
            next unless resolved

            handler_path, function_name = resolved
            next unless File.exists?(handler_path)

            handler_source = fetch_file_content(handler_path)
            handler_lines = handler_source.lines
            function_def_index = find_function_def(handler_lines, function_name)
            next if function_def_index.nil?
          end

          codeblock = parse_code_block(handler_lines[function_def_index..])
          next if codeblock.nil?
          codeblock_lines = codeblock.split("\n")
          handler_callees = build_callees_from(
            codeblock,
            function_def_index,
            handler_path,
            definition_base_path: definition_base_path,
            source: handler_source
          )

          registration_prefixes.each do |registration_prefix|
            full_prefix = compose_sanic_prefix(router_name, registration_prefix, prefix, blueprint_group_prefixes, blueprint_versions)
            get_endpoints("GET", route_path, extra_params, codeblock_lines, full_prefix, "websocket").each do |endpoint|
              endpoint.details = Details.new(PathInfo.new(path, line_index + 1))
              handler_callees.each { |c| endpoint.push_callee(c) }
              result << endpoint
            end
          end
        end
      end

      @programmatic_class_routes.each do |router_name, router_info_list|
        router_info_list.each do |route_info|
          line_index, path, route_path, extra_params, class_name = route_info
          source = fetch_file_content(path)
          lines = source.lines
          definition_base_path = python_base_path_for(path)
          api_instances = path_api_instances[path]
          prefix = api_instances[router_name]? || ""
          registration_prefixes = blueprint_registration_prefixes[{definition_base_path, router_name}]? || [""]

          class_def_index = find_class_def(lines, class_name)
          next if class_def_index.nil?

          class_indent = lines[class_def_index].size - lines[class_def_index].lstrip.size
          methods = extract_methods_from_extra_params(extra_params)
          methods = find_class_http_methods(lines, class_def_index, class_indent) if methods.empty?

          methods.uniq.each do |http_method|
            method_def_index = find_class_method_def(lines, class_def_index, class_indent, http_method.downcase)
            next if method_def_index.nil?

            codeblock = parse_code_block(lines[method_def_index..])
            next if codeblock.nil?
            codeblock_lines = codeblock.split("\n")
            handler_callees = build_callees_from(
              codeblock,
              method_def_index,
              path,
              definition_base_path: definition_base_path,
              source: source
            )

            route_extra_params = "methods=['#{http_method.upcase}']"
            registration_prefixes.each do |registration_prefix|
              full_prefix = compose_sanic_prefix(router_name, registration_prefix, prefix, blueprint_group_prefixes, blueprint_versions)
              get_endpoints(http_method, route_path, route_extra_params, codeblock_lines, full_prefix).each do |endpoint|
                endpoint.details = Details.new(PathInfo.new(path, line_index + 1))
                handler_callees.each { |c| endpoint.push_callee(c) }
                result << endpoint
              end
            end
          end
        end
      end

      @static_routes.each do |router_name, static_info_list|
        static_info_list.each do |static_info|
          line_index, path, static_path = static_info
          definition_base_path = python_base_path_for(path)
          api_instances = path_api_instances[path]
          prefix = api_instances[router_name]? || ""
          registration_prefixes = blueprint_registration_prefixes[{definition_base_path, router_name}]? || [""]

          registration_prefixes.each do |registration_prefix|
            full_prefix = compose_sanic_prefix(router_name, registration_prefix, prefix, blueprint_group_prefixes, blueprint_versions)
            endpoint_path = static_route_path(join_paths(full_prefix, static_path))
            result << Endpoint.new(endpoint_path, "GET", Details.new(PathInfo.new(path, line_index + 1)))
          end
        end
      end

      result
    end

    private def parse_static_route(line : ::String) : Tuple(::String, ::String)?
      call_match = line.match(STATIC_CALL_RE)
      return unless call_match

      router_name = call_match[1]
      args = split_python_arguments(call_match[2])
      static_path = extract_keyword_string(args, "uri") ||
                    extract_keyword_string(args, "path") ||
                    args[0]?.try { |arg| extract_python_string(arg) } || ""
      return if static_path.empty?

      {router_name, static_path}
    end

    private def parse_programmatic_class_route(line : ::String) : Tuple(::String, ::String, ::String, ::String)?
      call_match = line.match(ADD_ROUTE_CALL_RE)
      return unless call_match

      router_name = call_match[1]
      args = split_python_arguments(call_match[2])
      class_name = extract_programmatic_handler_class(args)
      route_path = extract_programmatic_route_path(args)
      return if class_name.empty? || route_path.empty?

      methods = extract_programmatic_methods(args)
      extra_params = "methods=[#{methods.map { |method| "'#{method}'" }.join(",")}]"
      {router_name, route_path, class_name, extra_params}
    end

    private def parse_programmatic_route(line : ::String) : Tuple(::String, ::String, ::String, ::String)?
      call_match = line.match(ADD_ROUTE_CALL_RE)
      return unless call_match

      router_name = call_match[1]
      args = split_python_arguments(call_match[2])
      handler_name = extract_programmatic_handler(args)
      route_path = extract_programmatic_route_path(args)
      return if handler_name.empty? || route_path.empty?

      methods = extract_programmatic_methods(args)
      methods = ["GET"] if methods.empty?
      extra_params = "methods=[#{methods.map { |method| "'#{method}'" }.join(",")}]"
      {router_name, route_path, handler_name, extra_params}
    end

    private def parse_programmatic_websocket_route(line : ::String) : Tuple(::String, ::String, ::String, ::String)?
      call_match = line.match(ADD_WEBSOCKET_ROUTE_CALL_RE)
      return unless call_match

      router_name = call_match[1]
      args = split_python_arguments(call_match[2])
      handler_name = extract_programmatic_handler(args)
      route_path = extract_programmatic_route_path(args)
      return if handler_name.empty? || route_path.empty?

      {router_name, route_path, handler_name, "methods=['GET']"}
    end

    private def extract_programmatic_handler_class(args : Array(::String)) : ::String
      handler = extract_keyword_expression(args, "handler") || args[0]?
      return "" unless handler

      if class_match = handler.strip.match(AS_VIEW_RE)
        return class_match[1]
      end

      ""
    end

    private def extract_programmatic_handler(args : Array(::String)) : ::String
      if handler = extract_keyword_expression(args, "handler")
        return clean_reference(handler)
      end

      return "" if args.empty?
      clean_reference(args[0])
    end

    private def extract_programmatic_route_path(args : Array(::String)) : ::String
      if uri = extract_keyword_string(args, "uri")
        return uri
      end
      if uri = extract_keyword_string(args, "uri_template")
        return uri
      end
      if path = extract_keyword_string(args, "path")
        return path
      end

      return "" if args.size < 2
      extract_python_string(args[1]) || ""
    end

    private def extract_programmatic_methods(args : Array(::String)) : Array(::String)
      expression = extract_keyword_expression(args, "methods")
      return [] of ::String unless expression

      methods = [] of ::String
      expression.scan(/['"]([A-Za-z]+)['"]/) do |method_match|
        methods << method_match[1].upcase
      end
      methods
    end

    # Memoized per keyword — the keyword set is tiny (`handler`, `uri`,
    # `path`, `methods`, ...) but this runs per argument of every
    # programmatic route.
    private def keyword_expression_regex(keyword : ::String) : Regex
      @keyword_regex_cache[keyword] ||= /^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m
    end

    private def extract_keyword_expression(args : Array(::String), keyword : ::String) : ::String?
      keyword_re = keyword_expression_regex(keyword)
      args.each do |arg|
        keyword_match = arg.match(keyword_re)
        return keyword_match[1].strip if keyword_match
      end

      nil
    end

    private def extract_keyword_string(args : Array(::String), keyword : ::String) : ::String?
      if expression = extract_keyword_expression(args, keyword)
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
      return reference if reference.matches?(DOTTED_REFERENCE_RE)

      ""
    end

    private def resolve_external_handler(handler_name : ::String,
                                         current_path : ::String,
                                         import_modules : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, ::String)?
      reference = handler_name.strip
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

    private def find_self_method_def(lines : Array(::String), route_line_index : Int32, handler_name : ::String) : Int32?
      return unless handler_name.starts_with?("self.")

      method_name = handler_name.split(".", 2)[1]?
      return if method_name.nil? || method_name.empty?

      class_scope = find_enclosing_class_scope(lines, route_line_index)
      return unless class_scope

      class_def_index, class_indent = class_scope
      find_class_method_def(lines, class_def_index, class_indent, method_name)
    end

    private def find_enclosing_class_scope(lines : Array(::String), line_index : Int32) : Tuple(Int32, Int32)?
      current_line = lines[line_index]?
      return unless current_line

      current_indent = current_line.index(/\S/) || 0
      i = line_index
      while i >= 0
        if class_match = lines[i].match(/^(\s*)class\s+/)
          class_indent = class_match[1].size
          return {i, class_indent} if class_indent < current_indent
        end
        i -= 1
      end

      nil
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

    private def find_function_def(lines : Array(::String), function_name : ::String) : Int32?
      # Compile the name-specific matcher once per call instead of on
      # every line, and gate it behind cheap substring necessary checks.
      function_def_re = /^\s*(?:async\s+)?def\s+#{Regex.escape(function_name)}\s*\(/
      lines.each_with_index do |line, index|
        next unless line.includes?("def") && line.includes?(function_name)
        if line.match(function_def_re)
          return index
        end
      end

      nil
    end

    private def find_class_def(lines : Array(::String), class_name : ::String) : Int32?
      lines.each_with_index do |line, index|
        stripped = line.lstrip
        class_prefix = "class #{class_name}"
        if stripped.starts_with?(class_prefix) &&
           (stripped.size == class_prefix.size || stripped[class_prefix.size].in?('(', ':', ' ', '\t'))
          return index
        end
      end

      nil
    end

    private def find_class_http_methods(lines : Array(::String), class_def_index : Int32, class_indent : Int32) : Array(::String)
      methods = [] of ::String
      i = class_def_index + 1
      while i < lines.size
        line = lines[i]
        if class_match = line.match(/(\s*)class\s+/)
          break if class_match[1].size <= class_indent
        end

        if method_match = line.match(/(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/)
          if method_match[1].size > class_indent
            method = HTTP_METHODS.find { |known| known.downcase == method_match[3].downcase }
            methods << method.upcase if method
          end
        end

        i += 1
      end

      methods
    end

    private def find_class_method_def(lines : Array(::String), class_def_index : Int32, class_indent : Int32, method_name : ::String) : Int32?
      # Compile the name-specific matcher once per call instead of on
      # every line, and gate it behind a cheap substring necessary check.
      method_def_re = /(\s*)(async\s+)?def\s+#{Regex.escape(method_name)}\s*\(/
      i = class_def_index + 1
      while i < lines.size
        line = lines[i]
        if class_match = line.match(/(\s*)class\s+/)
          break if class_match[1].size <= class_indent
        end

        if line.includes?(method_name) && (method_match = line.match(method_def_re))
          return i if method_match[1].size > class_indent
        end

        i += 1
      end

      nil
    end

    private def extract_methods_from_extra_params(extra_params : ::String) : Array(::String)
      methods = [] of ::String
      methods_match = extra_params.match(/methods\s*=\s*\[([^\]]*)\]/)
      return methods unless methods_match

      methods_match[1].scan(/['"]([^'"]*)['"']/) do |method_match|
        methods << method_match[1].upcase
      end

      methods
    end

    private def collect_blueprint_registrations(source : ::String,
                                                registrations : Hash(ScopedNameKey, Array(::String)),
                                                base_path : ::String)
      source.scan(BLUEPRINT_CALL_RE) do |match|
        next if match.size < 3
        blueprint_name = match[1]
        tail = match[2]
        prefix = ""
        if prefix_match = tail.match(/url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/)
          prefix = prefix_match[1]
        end

        key = {base_path, blueprint_name}
        registrations[key] ||= [] of ::String
        registrations[key] << prefix unless registrations[key].includes?(prefix)
      end
    end

    BLUEPRINT_GROUP_RE = /(?:#{PYTHON_VAR_NAME_REGEX}\s*=\s*)?Blueprint\s*\.\s*group\s*\((.*?)\)/m
    BLUEPRINT_CTOR_RE  = /(#{PYTHON_VAR_NAME_REGEX})\s*=\s*(?:sanic\.)?Blueprint\s*\((.*?)\)/m

    # `Blueprint.group(bp1, bp2, url_prefix="/api", version=1)` shares its
    # url_prefix and version with each member blueprint; `Blueprint(name,
    # version=2)` versions a single blueprint. Collect both so the route
    # emitter can prepend the group prefix and the `/v<n>` version segment.
    private def collect_blueprint_groups_and_versions(source : ::String,
                                                      group_prefixes : Hash(::String, ::String),
                                                      versions : Hash(::String, ::String))
      source.scan(BLUEPRINT_GROUP_RE) do |match|
        args = match[1]
        group_prefix = args.match(/url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/).try(&.[1]) || ""
        group_version = args.match(/\bversion\s*=\s*['"]?(\w+)['"]?/).try(&.[1])
        # Positional bare-identifier args before the first keyword are members.
        args.split(',').each do |arg|
          name = arg.strip
          break if name.includes?("=") # reached keyword args
          next unless name.matches?(/\A#{PYTHON_VAR_NAME_REGEX}\z/)
          group_prefixes[name] = group_prefix unless group_prefix.empty?
          versions[name] ||= group_version if group_version
        end
      end

      source.scan(BLUEPRINT_CTOR_RE) do |match|
        name = match[1]
        if v = match[2].match(/\bversion\s*=\s*['"]?(\w+)['"]?/)
          versions[name] ||= v[1]
        end
      end
    end

    # Compose a route's full prefix: `/v<version>` (outermost) + group
    # url_prefix + registration prefix + the blueprint's own url_prefix.
    private def compose_sanic_prefix(router_name : ::String,
                                     registration_prefix : ::String,
                                     prefix : ::String,
                                     group_prefixes : Hash(::String, ::String),
                                     versions : Hash(::String, ::String),
                                     route_version : ::String? = nil) : ::String
      base = join_paths(group_prefixes[router_name]? || "", join_paths(registration_prefix, prefix))
      version = route_version || versions[router_name]?
      version && !version.empty? ? join_paths("/v#{version}", base) : base
    end

    private def fetch_file_content(path : ::String) : ::String
      unless @file_content_cache.has_key?(path)
        @file_content_cache[path] = read_file_content(path)
      end
      @file_content_cache[path]
    end

    private def extract_params_from_decorator(path : ::String, lines : Array(::String), line_index : Int32, direction : Symbol = :down) : Tuple(Array(Param), Int32)
      # params stays empty for Sanic (unlike Flask which does decorator-level
      # param extraction). The adapter pulls params from the function body later.
      {[] of Param, Noir::PythonRouteExtractor.find_def_line(lines, line_index, direction)}
    end

    private def get_endpoints(method : String, route_path : String, extra_params : String, codeblock_lines : Array(String), prefix : String = "", route_attr : String = "")
      endpoints = [] of Endpoint
      params = [] of Param

      # Extract HTTP methods from extra_params
      methods = [method]
      if extra_params.includes?("methods")
        methods_match = extra_params.match /methods\s*=\s*\[([^\]]*)\]/
        if methods_match
          methods_str = methods_match[1]
          methods = methods_str.scan(/['"]([^'"]*)['"']/).map(&.[1]).map(&.upcase)
        end
      end

      # Parse the codeblock for request parameter usage
      json_variable_names = [] of String

      # First pass: identify JSON variable assignments
      codeblock_lines.each do |code_line|
        # Look for patterns like: record = request.json
        json_match = code_line.match /([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*request\.json/
        if json_match
          json_variable_names << json_match[1]
        end
      end

      # Second pass: extract parameters
      codeblock_lines.each do |code_line|
        REQUEST_PARAM_FIELD_PATTERNS.each do |guard, param_type, param_regex, bracket_regex|
          if code_line.includes?(guard)
            # Extract parameter access patterns
            code_line.scan(param_regex) do |match|
              param_name = match[1]
              param = Param.new(param_name, "", param_type)
              params << param unless params.any? { |p| p.name == param_name && p.param_type == param_type }
            end

            # Handle bracket notation: request.args['param']
            code_line.scan(bracket_regex) do |match|
              param_name = match[1]
              param = Param.new(param_name, "", param_type)
              params << param unless params.any? { |p| p.name == param_name && p.param_type == param_type }
            end
          end
        end

        # Extract JSON parameters from variable usage
        json_variable_names.each do |json_var|
          # The var name is a necessary substring for either pattern.
          next unless code_line.includes?(json_var)
          bracket_regex, get_regex = json_var_regexes(json_var)

          # Look for patterns like: json_var['param_name']
          code_line.scan(bracket_regex) do |match|
            param_name = match[1]
            param = Param.new(param_name, "", "json")
            params << param unless params.any? { |p| p.name == param_name && p.param_type == "json" }
          end

          # Look for patterns like: json_var.get('param_name')
          code_line.scan(get_regex) do |match|
            param_name = match[1]
            param = Param.new(param_name, "", "json")
            params << param unless params.any? { |p| p.name == param_name && p.param_type == "json" }
          end
        end
      end

      # Create endpoints for each method
      methods.each do |http_method|
        # Create endpoint with the prefix
        full_path = normalize_sanic_path_params(join_paths(prefix, route_path))
        filtered_params = get_filtered_params(http_method, params.dup)
        endpoint = Endpoint.new(full_path, http_method, filtered_params)
        endpoint.protocol = "ws" if route_attr == "websocket"
        endpoints << endpoint
      end

      endpoints
    end

    # Memoized per JSON-variable name (`data`, `body`, ...): the patterns
    # interpolate a discovered name so they can't be class constants, but
    # handler bodies reuse the same few names across a whole project.
    private def json_var_regexes(json_var : ::String) : Tuple(Regex, Regex)
      @json_var_regex_cache[json_var] ||= {
        /#{json_var}\[['"']([^'"']+)['"']\]/,
        /#{json_var}\.get\(['"']([^'"']+)['"']\)/,
      }
    end

    private def join_paths(prefix : ::String, path : ::String) : ::String
      return normalize_path(path) if prefix.empty?
      return normalize_path(prefix) if path.empty?

      normalize_path("#{prefix}/#{path}")
    end

    private def static_route_path(path : ::String) : ::String
      normalized = normalize_path(path)
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
    end

    private def normalize_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    private def normalize_sanic_path_params(path : ::String) : ::String
      path.gsub(/<([A-Za-z_][A-Za-z0-9_]*)(?::[^>]+)?>/) do |_match|
        "{#{$1}}"
      end
    end

    # Filters the parameters based on the HTTP method (similar to Flask analyzer)
    private def get_filtered_params(method : String, params : Array(Param)) : Array(Param)
      filtered_params = Array(Param).new
      upper_method = method.upcase

      params.each do |param|
        is_support_param = false
        support_methods = REQUEST_PARAM_TYPES.fetch(param.param_type, nil)
        if !support_methods.nil?
          support_methods.each do |support_method|
            if upper_method == support_method.upcase
              is_support_param = true
            end
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

        if is_support_param
          filtered_params << param
        end
      end

      filtered_params
    end

    private def parse_code_block(lines : Array(String)) : String?
      return if lines.empty?

      # Find the indentation of the function definition
      def_line = lines.first
      return unless def_line.includes?("def ")

      base_indent = def_line.index(/\S/) || 0
      codeblock_lines = [] of String

      # Add the function definition line
      codeblock_lines << def_line

      # Collect all lines that belong to this function (same or greater indentation)
      lines[1..].each do |line|
        if line.strip.empty?
          codeblock_lines << line
          next
        end

        current_indent = line.index(/\S/) || 0
        if current_indent > base_indent
          codeblock_lines << line
        else
          break
        end
      end

      codeblock_lines.join("\n")
    end
  end
end
