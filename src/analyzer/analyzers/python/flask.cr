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
      "cookie"  => {nil, "cookie"},
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

    def analyze
      flask_instances = Hash(::String, ::String).new
      flask_instances["app"] ||= "" # Common flask instance name
      blueprint_prefixes = Hash(::String, ::String).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new
      register_blueprint = Hash(::String, Hash(::String, ::String)).new

      # Iterate through all Python files in all base paths
      base_paths.each do |current_base_path|
        Dir.glob("#{current_base_path}/**/*.py") do |path|
          next if File.directory?(path)
          next if path.includes?("/site-packages/")
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            lines = file.each_line.to_a
            next unless lines.any?(&.includes?("flask"))
            api_instances = Hash(::String, ::String).new
            path_api_instances[path] = api_instances

          lines.each_with_index do |line, line_index|
            line = line.gsub(" ", "") # remove spaces for easier regex matching

            # Identify Flask instance assignments
            flask_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask\.)?Flask\(/
            if flask_match
              flask_instance_name = flask_match[1]
              api_instances[flask_instance_name] ||= ""
            end

            # Identify Blueprint instance assignments
            blueprint_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask\.)?Blueprint\(/
            if blueprint_match
              prefix = ""
              blueprint_instance_name = blueprint_match[1]
              param_codes = line.split("Blueprint", 2)[1]
              prefix_match = param_codes.match /url_prefix=[rf]?['"]([^'"]*)['"]/
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
                route_paths = view_registration_match[1]
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
              url_prefix_match = line.match /url_prefix=[rf]?['"]([^'"]*)['"]/
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
                route_path = _match[2]
                extra_params = _match[3]
                router_info = Tuple(Int32, ::String, ::String, ::String).new(line_index, path, route_path, extra_params)
                @routes[router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String)
                @routes[router_name] << router_info
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
          indent = lines[class_def_index].index("def") || 0
          unless lines[class_def_index].lstrip.starts_with?("def ")
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
            def_match = lines[i].match /(\s*)def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
            if def_match
              # Stop when the indentation is less than or equal to the class indentation
              break if is_class_router && def_match[1].size <= indent

              # Stop when the first function is found
              function_name_locations << Tuple.new(i, def_match[2])
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
      suspicious_params = [] of Param

      if !prefix.ends_with?("/") && !route_path.starts_with?("/")
        prefix = "#{prefix}/"
      end

      # Parse declared methods from route decorator
      methods_match = extra_params.match /methods\s*=\s*(.*)/
      if !methods_match.nil? && methods_match.size == 2
        declare_methods = methods_match[1].downcase
        HTTP_METHODS.each do |method_name|
          if declare_methods.includes? method_name
            methods << method_name.upcase
          end
        end
      else
        methods << method.upcase
      end

      json_variable_names = [] of ::String
      # Parse JSON variable names
      codeblock_lines.each do |codeblock_line|
        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*json\.loads\(request\.data/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end

        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*request\.json/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
      end

      # Parse declared parameters
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

              if matches.size > 0
                break
              end
            end
          end

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            param_name = parameter_match[1]

            suspicious_params << Param.new(param_name, "", noir_param_type)
          end
        end
      end

      methods.uniq.each do |http_method_name|
        route_url = "#{prefix}#{route_path}"
        route_url = "/#{route_url}" unless route_url.starts_with?("/")

        params = get_filtered_params(http_method_name, suspicious_params)
        endpoints << Endpoint.new(route_url.gsub("//", "/"), http_method_name, params)
      end

      endpoints
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
