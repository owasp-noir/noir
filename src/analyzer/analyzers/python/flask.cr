require "../../../models/analyzer"
require "../../../minilexers/python"
require "../../../miniparsers/python"
require "./python"

module Analyzer::Python
  class Flask < Python
    # Reference: https://stackoverflow.com/a/16664376
    # Reference: https://tedboy.github.io/flask/generated/generated/flask.Request.html
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

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "json"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    @file_content_cache = Hash(::String, ::String).new
    @parsers = Hash(::String, PythonParser).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String))).new
    @class_views = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String)))).new

    def analyze
      flask_instances = Hash(::String, ::String).new
      flask_instances["app"] ||= "" # Common flask instance name
      blueprint_prefixes = Hash(::String, ::String).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new
      register_blueprint = Hash(::String, Hash(::String, ::String)).new

      # Iterate through all Python files in all base paths
      base_paths.each do |current_base_path|
        Dir.glob("#{escape_glob_path(current_base_path)}/**/*.py") do |path|
          next if File.directory?(path)
          next if path.includes?("/site-packages/")
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            lines = file.each_line.to_a
            next unless lines.any?(&.includes?("flask"))
            api_instances = Hash(::String, ::String).new
            path_api_instances[path] = api_instances
            view_assignments = Hash(::String, ::String).new # Maps view_var -> ClassName (per-file scope)

            lines.each_with_index do |original_line, line_index|
              line = original_line.gsub(" ", "") # remove spaces for easier regex matching

              # Identify Flask instance assignments
              flask_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask\.)?Flask\(/
              if flask_match
                flask_instance_name = flask_match[1]
                api_instances[flask_instance_name] ||= ""
                flask_instances[flask_instance_name] ||= ""
              end

              # Identify Blueprint instance assignments
              blueprint_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask\.)?Blueprint\(/
              if blueprint_match
                prefix = ""
                blueprint_instance_name = blueprint_match[1]
                param_codes = original_line.split("Blueprint", 2)[1]
                prefix_match = param_codes.match /url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/
                if !prefix_match.nil? && prefix_match.size == 2
                  prefix = prefix_match[1]
                end

                blueprint_prefixes[blueprint_instance_name] ||= prefix
                api_instances[blueprint_instance_name] ||= prefix
              end

              # Identify Api instance assignments
              init_app_match = line.match /(#{PYTHON_VAR_NAME_REGEX})\.init_app\((#{PYTHON_VAR_NAME_REGEX})/
              if init_app_match
                api_instance_name = init_app_match[1]
                parser = get_parser(path)
                if parser.@global_variables.has_key?(api_instance_name)
                  gv = parser.@global_variables[api_instance_name]
                  api_instances[api_instance_name] ||= ""
                end
              end

              # Api from flask instance
              flask_instances.each do |_flask_instance_name, _prefix|
                api_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask_restx\.)?Api\((app=)?#{_flask_instance_name}/
                if api_match
                  api_instance_name = api_match[1]
                  api_instances[api_instance_name] ||= _prefix
                end
              end

              # Api from blueprint instance
              blueprint_prefixes.each do |_blueprint_instance_name, _prefix|
                api_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask_restx\.)?Api\((app=)?#{_blueprint_instance_name}/
                if api_match
                  api_instance_name = api_match[1]
                  api_instances[api_instance_name] ||= _prefix
                end
              end

              # Api Namespace
              api_instances.each do |_api_instance_name, _prefix|
                add_namespace_match = line.match /(#{_api_instance_name})\.add_namespace\((#{PYTHON_VAR_NAME_REGEX})/
                if add_namespace_match
                  parser = get_parser(path)
                  if parser.@global_variables.has_key?(add_namespace_match[2])
                    gv = parser.@global_variables[add_namespace_match[2]]
                    if gv.type == "Namespace"
                      api_instances[gv.name] = extract_namespace_prefix(parser, add_namespace_match[2], _prefix)
                    end
                  end
                end
              end

              # Temporary Addition: register_view
              blueprint_prefixes.each do |blueprint_name, blueprint_prefix|
                view_registration_match = line.match /#{blueprint_name},routes=(.*)\)/
                if view_registration_match
                  # Re-extract route paths from original line to preserve spaces in paths
                  original_registration_match = original_line.match /#{blueprint_name}\s*,\s*routes\s*=\s*(.*)\)/
                  route_paths = original_registration_match ? original_registration_match[1] : view_registration_match[1]
                  route_paths.scan /['"]([^'"]*)['"]/ do |path_str_match|
                    if !path_str_match.nil? && path_str_match.size == 2
                      route_path = path_str_match[1]
                      # Parse methods from reference views (TODO)
                      route_url = "#{blueprint_prefix}#{route_path}"
                      route_url = "/#{route_url}" unless route_url.starts_with?("/")
                      details = Details.new(PathInfo.new(path, line_index + 1))
                      result << Endpoint.new(route_url, "GET", details)
                    end
                  end
                end
              end

              # Identify Blueprint registration
              register_blueprint_match = line.match /(#{PYTHON_VAR_NAME_REGEX})\.register_blueprint\((#{DOT_NATION})/
              if register_blueprint_match
                url_prefix_match = original_line.match /url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/
                if url_prefix_match
                  blueprint_name = register_blueprint_match[2]
                  parser = get_parser(path)
                  if parser.@global_variables.has_key?(blueprint_name)
                    gv = parser.@global_variables[blueprint_name]
                    if gv.type == "Blueprint"
                      register_blueprint[gv.path] ||= Hash(::String, ::String).new
                      register_blueprint[gv.path][blueprint_name] = url_prefix_match[1]
                    end
                  end
                end
              end

              # Identify Flask route decorators
              line.scan(/@(#{PYTHON_VAR_NAME_REGEX})\.route\([rf]?['"]([^'"]*)['"](.*)/) do |_match|
                if _match.size > 0
                  router_name = _match[1]
                  extra_params = _match[3]
                  # Extract route path from original line to preserve spaces in paths
                  original_route_match = original_line.match /@#{_match[1]}\.route\(\s*[rf]?['"]([^'"]*)['"]/
                  route_path = original_route_match ? original_route_match[1] : _match[2]
                  router_info = Tuple(Int32, ::String, ::String, ::String).new(line_index, path, route_path, extra_params)
                  @routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String)
                  @routes[router_name] << router_info
                end
              end

              # Also detect method-specific decorators like @app.get, @app.post, etc.
              HTTP_METHODS.each do |method|
                line.scan(/@(#{PYTHON_VAR_NAME_REGEX})\.#{method.downcase}\([rf]?['"]([^'"]*)['"](.*)/) do |_match|
                  if _match.size > 0
                    router_name = _match[1]
                    extra_params = "methods=['#{method.upcase}']"
                    # Extract route path from original line to preserve spaces in paths
                    original_route_match = original_line.match /@#{_match[1]}\.#{method.downcase}\(\s*[rf]?['"]([^'"]*)['"]/
                    route_path = original_route_match ? original_route_match[1] : _match[2]
                    router_info = Tuple(Int32, ::String, ::String, ::String).new(line_index, path, route_path, extra_params)
                    @routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String)
                    @routes[router_name] << router_info
                  end
                end
              end

              # Identify view assignments: view_var = ClassName.as_view('name')
              # Note: spaces are already removed from line at this point
              view_assign_match = line.match /(#{PYTHON_VAR_NAME_REGEX})=(#{PYTHON_VAR_NAME_REGEX})\.as_view\(/
              if view_assign_match
                view_var = view_assign_match[1]
                class_name = view_assign_match[2]
                view_assignments[view_var] = class_name
              end

              # Identify add_url_rule() registrations for class-based views
              # Match the call generically, then extract rule/view_func from any argument position
              line.scan(/(#{PYTHON_VAR_NAME_REGEX})\.add_url_rule\((.+)\)/) do |_match|
                next if _match.size == 0
                router_name = _match[1]
                args_str = _match[2]

                # Extract route path from original line to preserve spaces in paths
                # Try rule= keyword first, then first positional string arg
                route_path = ""
                original_args_match = original_line.match /\.add_url_rule\((.+)\)/
                original_args = original_args_match ? original_args_match[1] : args_str
                rule_match = original_args.match /rule\s*=\s*[rf]?['"]([^'"]*)['"]/
                if rule_match
                  route_path = rule_match[1]
                else
                  first_str_match = original_args.match /^\s*[rf]?['"]([^'"]*)['"]/
                  route_path = first_str_match[1] if first_str_match
                end
                next if route_path.empty?

                class_name = ""
                view_name = ""

                # Extract view_func: try keyword form, then positional form
                # Keyword: view_func=ClassName.as_view('name') or view_func=view_var
                view_func_match = args_str.match /view_func=(#{PYTHON_VAR_NAME_REGEX})\.as_view\([rf]?['"]([^'"]*)['"]\)/
                if view_func_match
                  class_name = view_func_match[1]
                  view_name = view_func_match[2]
                else
                  view_var_match = args_str.match /view_func=(#{PYTHON_VAR_NAME_REGEX})[,\)]/
                  if view_var_match
                    view_var = view_var_match[1]
                    if view_assignments.has_key?(view_var)
                      class_name = view_assignments[view_var]
                      view_name = view_var
                    end
                  end
                end

                # Positional: add_url_rule('/path', 'endpoint', view_var) or
                #             add_url_rule('/path', 'endpoint', Class.as_view('name'))
                # After space-stripping: '/path','endpoint',view_var
                if class_name.empty?
                  # Split positional args respecting nested parentheses
                  positional_parts = [] of ::String
                  remaining = args_str
                  while !remaining.empty?
                    # Match a quoted string argument
                    str_match = remaining.match /^[rf]?['"][^'"]*['"]/
                    if str_match
                      positional_parts << str_match[0]
                      remaining = remaining[str_match[0].size..]
                      remaining = remaining.lstrip(',')
                      next
                    end
                    # Stop at keyword arguments
                    break if remaining.match /^#{PYTHON_VAR_NAME_REGEX}=/
                    # Match an expression, tracking paren depth to handle nested calls like .as_view('name')
                    paren_depth = 0
                    end_idx = 0
                    while end_idx < remaining.size
                      ch = remaining[end_idx]
                      if ch == '('
                        paren_depth += 1
                      elsif ch == ')'
                        break if paren_depth == 0
                        paren_depth -= 1
                      elsif ch == ',' && paren_depth == 0
                        break
                      end
                      end_idx += 1
                    end
                    if end_idx > 0
                      positional_parts << remaining[0...end_idx]
                      remaining = remaining[end_idx..]
                      remaining = remaining.lstrip(',')
                      next
                    end
                    break
                  end

                  # Flask signature: add_url_rule(rule, endpoint=None, view_func=None, ...)
                  # 2nd or 3rd positional arg can be view_func
                  view_arg = if positional_parts.size >= 3
                               positional_parts[2]
                             elsif positional_parts.size == 2
                               positional_parts[1]
                             else
                               ""
                             end

                  unless view_arg.empty?
                    as_view_match = view_arg.match /(#{PYTHON_VAR_NAME_REGEX})\.as_view\([rf]?['"]([^'"]*)['"]\)/
                    if as_view_match
                      class_name = as_view_match[1]
                      view_name = as_view_match[2]
                    elsif view_assignments.has_key?(view_arg)
                      class_name = view_assignments[view_arg]
                      view_name = view_arg
                    end
                  end
                end

                if !class_name.empty?
                  # Extract methods list
                  methods = [] of ::String
                  methods_match = args_str.match /methods=[\[\(](.*?)[\]\)]/
                  if methods_match
                    methods_str = methods_match[1]
                    methods_str.scan(/['"]([A-Z]+)['"]/) do |method_match|
                      methods << method_match[1]
                    end
                  end

                  # Store class view registration
                  class_view_info = Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String)).new(
                    line_index, path, route_path, class_name, view_name, methods
                  )
                  @class_views[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, ::String, Array(::String))
                  @class_views[router_name] << class_view_info
                end
              end
            end
          end
        end
      end

      # Update the API instances with the blueprint prefixes
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

      # Iterate through the routes and extract endpoints
      @routes.each do |router_name, router_info_list|
        router_info_list.each do |router_info|
          line_index, path, route_path, extra_params = router_info
          lines = fetch_file_content(path).lines
          expect_params, class_def_index = extract_params_from_decorator(path, lines, line_index)
          api_instances = path_api_instances[path]
          if api_instances.has_key?(router_name)
            prefix = api_instances[router_name]
          else
            parser = get_parser(path)
            prefix = extract_namespace_prefix(parser, router_name, "")
          end

          is_class_router = false
          indent = lines[class_def_index].size - lines[class_def_index].lstrip.size
          unless lines[class_def_index].lstrip.starts_with?("def ") || lines[class_def_index].lstrip.starts_with?("async def ")
            if lines[class_def_index].lstrip.starts_with?("class ")
              indent = lines[class_def_index].size - lines[class_def_index].lstrip.size
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

            # Get the HTTP method from the function name when it is not specified in the route decorator
            method = HTTP_METHODS.find { |http_method| _function_name.downcase == http_method.downcase } || "GET"
            get_endpoints(method, route_path, extra_params, codeblock_lines, prefix).each do |endpoint|
              details = Details.new(PathInfo.new(path, line_index + 1))
              endpoint.details = details

              # Add expect params as endpoint params
              if expect_params.size > 0
                expect_params.each do |param|
                  # Change the param type to form if the endpoint method is POST
                  if endpoint.method == "GET"
                    endpoint.push_param(Param.new(param.name, param.value, "query"))
                  else
                    endpoint.push_param(Param.new(param.name, param.value, "form"))
                  end
                end
              end
              result << endpoint
            end
          end
        end
      end

      # Process class-based views from add_url_rule() registrations
      @class_views.each do |router_name, class_view_list|
        class_view_list.each do |class_view_info|
          _, path, route_path, class_name, _, methods = class_view_info

          api_instances = path_api_instances[path]
          prefix = api_instances.has_key?(router_name) ? api_instances[router_name] : ""

          # Try to use parser to find class definition, otherwise assume same file
          class_file = path
          parser = get_parser(path)
          if parser.@global_variables.has_key?(class_name)
            gv = parser.@global_variables[class_name]
            class_file = gv.path
          end

          class_lines = fetch_file_content(class_file).lines

          # Find class definition line
          class_def_index = -1
          class_lines.each_with_index do |line, idx|
            stripped = line.lstrip
            class_prefix = "class #{class_name}"
            if stripped.starts_with?(class_prefix) &&
               (stripped.size == class_prefix.size || stripped[class_prefix.size].in?('(', ':', ' ', '\t'))
              class_def_index = idx
              break
            end
          end

          next if class_def_index == -1

          indent = class_lines[class_def_index].size - class_lines[class_def_index].lstrip.size

          # If no explicit methods, infer from class method definitions
          if methods.empty?
            i = class_def_index + 1
            while i < class_lines.size
              infer_match = class_lines[i].match /(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
              if infer_match && infer_match[1].size > indent
                method_name = infer_match[3]
                inferred_method = HTTP_METHODS.find { |m| m.downcase == method_name.downcase }
                methods << inferred_method.upcase if inferred_method
              end
              # Stop if we hit another class at same or higher level
              class_match = class_lines[i].match /(\s*)class\s+/
              break if class_match && class_match[1].size <= indent && i != class_def_index
              i += 1
            end
            # Default to GET if no HTTP methods inferred (matches Flask behavior)
            methods << "GET" if methods.empty?
          end

          # Process each declared method
          methods.uniq.each do |http_method|
            method_name = http_method.downcase

            # Find method definition in class
            method_def_index = -1
            i = class_def_index + 1

            while i < class_lines.size
              method_match = class_lines[i].match /(\s*)(async\s+)?def\s+#{method_name}\s*\(/
              if method_match
                # Check it's a method of this class (correct indentation)
                method_indent = method_match[1].size
                if method_indent > indent
                  method_def_index = i
                  break
                end
              end

              # Stop if we hit another class at same or higher level
              class_match = class_lines[i].match /(\s*)class\s+/
              if class_match && class_match[1].size <= indent
                break
              end

              i += 1
            end

            next if method_def_index == -1

            # Parse method code block
            codeblock = parse_code_block(class_lines[method_def_index..])
            next if codeblock.nil?
            codeblock_lines = codeblock.split("\n")

            # Generate endpoint with parameters
            route_url = "#{prefix}#{route_path}"
            route_url = "/#{route_url}" unless route_url.starts_with?("/")
            route_url = route_url.gsub("//", "/")

            # Extract parameters from method body
            suspicious_params = extract_request_params(codeblock_lines)
            params = get_filtered_params(http_method, suspicious_params)
            details = Details.new(PathInfo.new(class_file, method_def_index + 1))
            endpoint = Endpoint.new(route_url, http_method, params)
            endpoint.details = details
            result << endpoint
          end
        end
      end

      Fiber.yield
      result
    end

    # Fetch content of a file and cache it
    private def fetch_file_content(path : ::String) : ::String
      @file_content_cache[path] ||= File.read(path, encoding: "utf-8", invalid: :skip)
    end

    # Create a Python parser for a given path and content
    def create_parser(path : ::String, content : ::String = "") : PythonParser
      content = fetch_file_content(path) if content.empty?
      lexer = PythonLexer.new
      @logger.debug "Tokenizing #{path}"
      tokens = lexer.tokenize(content)
      @logger.debug "Parsing #{path}"
      parser = PythonParser.new(path, tokens, @parsers)
      @logger.debug "Parsed #{path}"
      parser
    end

    # Get a parser for a given path
    def get_parser(path : ::String, content : ::String = "") : PythonParser
      @parsers[path] ||= create_parser(path, content)
      @parsers[path]
    end

    # Extracts endpoint information from the given route and code block
    def get_endpoints(method : ::String, route_path : ::String, extra_params : ::String, codeblock_lines : Array(::String), prefix : ::String)
      endpoints = [] of Endpoint
      methods = [] of ::String

      if !prefix.ends_with?("/") && !route_path.starts_with?("/")
        prefix = "#{prefix}/"
      end

      # Parse declared methods from route decorator
      methods_match = extra_params.match /methods\s*=\s*(.*)/
      if !methods_match.nil? && methods_match.size == 2
        methods_match[1].scan(/['"]([^'"]*)['"']/) do |m|
          method_name = m[1].upcase
          methods << method_name if HTTP_METHODS.any? { |hm| hm.upcase == method_name }
        end
      end
      if methods.empty?
        methods << method.upcase
      end

      suspicious_params = extract_request_params(codeblock_lines)

      methods.uniq.each do |http_method_name|
        route_url = "#{prefix}#{route_path}"
        route_url = "/#{route_url}" unless route_url.starts_with?("/")

        params = get_filtered_params(http_method_name, suspicious_params)
        endpoints << Endpoint.new(route_url.gsub("//", "/"), http_method_name, params)
      end

      endpoints
    end

    # Extracts request parameters from a code block by detecting JSON variable
    # assignments and scanning for request.field access patterns.
    private def extract_request_params(codeblock_lines : Array(::String)) : Array(Param)
      params = [] of Param
      json_variable_names = [] of ::String

      # Parse JSON variable names (e.g. data = json.loads(request.data), data = request.json)
      codeblock_lines.each do |codeblock_line|
        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*json\.loads\(request\.data/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*request\.(?:get_json\([^)]*\)|json)/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
      end

      # Parse declared parameters from request field access patterns
      codeblock_lines.each do |codeblock_line|
        REQUEST_PARAM_FIELDS.each do |field_name, tuple|
          _, noir_param_type = tuple
          matches = codeblock_line.scan(/request\.#{field_name}\[[rf]?['"]([^'"]*)['"]\]/)
          if matches.size == 0
            matches = codeblock_line.scan(/request\.#{field_name}\.get\([rf]?['"]([^'"]*)['"]/)
          end
          if matches.size == 0
            noir_param_type = "json"
            json_variable_names.each do |json_variable_name|
              matches = codeblock_line.scan(/[^a-zA-Z_]#{json_variable_name}\[[rf]?['"]([^'"]*)['"]\]/)
              if matches.size == 0
                matches = codeblock_line.scan(/[^a-zA-Z_]#{json_variable_name}\.get\([rf]?['"]([^'"]*)['"]/)
              end
              break if matches.size > 0
            end
          end

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            param_name = parameter_match[1]
            params << Param.new(param_name, "", noir_param_type)
          end
        end
      end

      params
    end

    # Filters the parameters based on the HTTP method
    def get_filtered_params(method : ::String, params : Array(Param)) : Array(Param)
      # Split to other module (duplicated method with analyzer_django)
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

    # Extracts parameters from the decorator
    def extract_params_from_decorator(path : ::String, lines : Array(::String), line_index : Int32, direction : Symbol = :down) : Tuple(Array(Param), Int32)
      params = [] of Param
      codeline_index = (direction == :down) ? line_index + 1 : line_index - 1

      # Iterate through the lines until the decorator ends
      while (direction == :down && codeline_index < lines.size) || (direction == :up && codeline_index >= 0)
        # Skip empty/blank lines
        if lines[codeline_index].strip.empty?
          codeline_index += (direction == :down ? 1 : -1)
          next
        end
        decorator_match = lines[codeline_index].match /\s*@/
        break if decorator_match.nil?

        # Extract parameters from the expect decorator
        # https://flask-restx.readthedocs.io/en/latest/swagger.html#the-api-expect-decorator
        expect_match = lines[codeline_index].match /\s*@.+\.expect\(\s*(#{DOT_NATION})/
        if !expect_match.nil?
          parser = get_parser(path)
          if parser.@global_variables.has_key?(expect_match[1])
            gv = parser.@global_variables[expect_match[1]]
            if gv.type == "Namespace.model"
              model = gv.value.split("model(", 2)[1]
              parameter_dict_literal = model.split("{", 1)[-1]

              field_pos_list = [] of Tuple(Int32, Int32)
              parameter_dict_literal.scan(/['"]([^'"]*)['"]:\s*fields\./) do |match|
                match_begin = match.begin(0)
                match_end = match.end(0)
                field_pos_list << Tuple.new(match_begin, match_end)
              end

              field_pos_list.each_with_index do |field_pos, index|
                field_begin_pos = field_pos[0]
                field_end_pos = -1
                if field_pos_list.size != 0 && index != field_pos_list.size - 1
                  next_field_start_pos = field_pos_list[index + 1][0]
                  field_end_pos += next_field_start_pos + field_pos[1]
                end

                field_literal = parameter_dict_literal[field_begin_pos..field_end_pos]
                field_key_literal, field_value_literal = field_literal.split(":", 2)
                field_key = field_key_literal.strip[1..-2]
                default_value = ""
                default_assign_match = /default=(.+)/.match(field_value_literal)
                if default_assign_match
                  rindex = default_assign_match[1].rindex(",")
                  rindex = default_assign_match[1].rindex(")") if rindex.nil?
                  unless rindex.nil?
                    default_value = default_assign_match[1][..rindex - 1].strip
                    if default_value[0] == "'" || default_value[0] == '"'
                      default_value = default_value[1..-2]
                    end
                  end
                end

                params << Param.new(field_key, default_value, "query")
              end
            end
          end
        end

        codeline_index += (direction == :down ? 1 : -1)
      end

      return params, [lines.size - 1, codeline_index].min
    end

    # Function to extract namespace from the parser and update the prefix
    private def extract_namespace_prefix(parser : PythonParser, key : ::String, _prefix : ::String) : ::String
      # Check if the parser's global variables contain the given key
      if parser.@global_variables.has_key?(key)
        gv = parser.@global_variables[key]

        # If the global variable is of type "Namespace"
        if gv.type == "Namespace"
          # Extract namespace value from the global variable
          namespace = gv.value.split("Namespace(", 2)[1]
          if namespace.includes?("path=")
            namespace = namespace.split("path=")[1].split(")")[0].split(",")[0]
          else
            namespace = namespace.split(",")[0].split(")")[0].strip
          end

          # Clean up the namespace string by removing surrounding quotes
          if namespace.starts_with?("'") || namespace.starts_with?("\"")
            namespace = namespace[1..]
          end
          if namespace.ends_with?("'") || namespace.ends_with?("\"")
            namespace = namespace[..-2]
          end

          _prefix = File.join(_prefix, namespace)
        end
      end
      _prefix
    end
  end
end
