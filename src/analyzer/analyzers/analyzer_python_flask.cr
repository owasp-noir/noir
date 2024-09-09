require "../../models/analyzer"
require "../../minilexers/python"
require "../../miniparsers/python"
require "./analyzer_python"

class AnalyzerFlask < AnalyzerPython
  # Reference: https://stackoverflow.com/a/16664376
  # Reference: https://tedboy.github.io/flask/generated/generated/flask.Request.html
  REQUEST_PARAM_FIELD_MAP = {
    "data"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
    "args"    => {["GET"], "query"},
    "form"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
    "files"   => {["POST", "PUT", "PATCH", "DELETE"], "form"},
    "values"  => {["GET", "POST", "PUT", "PATCH", "DELETE"], "query"},
    "json"    => {["POST", "PUT", "PATCH", "DELETE"], "json"},
    "cookie"  => {nil, "cookie"},
    "headers" => {nil, "header"},
  }

  REQUEST_PARAM_TYPE_MAP = {
    "query"  => nil,
    "form"   => ["POST", "PUT", "PATCH", "DELETE"],
    "json"   => ["POST", "PUT", "PATCH", "DELETE"],
    "cookie" => nil,
    "header" => nil,
  }

  FILE_CONTENT_CACHE = Hash(String, String).new
  PARSER_MAP         = Hash(String, PythonParser).new
  ROUTER_MAP         = Hash(String, Array(Tuple(Int32, String, String, String))).new

  def analyze
    flask_instance_map = Hash(String, String).new
    flask_instance_map["app"] ||= "" # Common flask instance name
    blueprint_prefix_map = Hash(String, String).new
    api_instance_map = Hash(String, String).new

    # Iterate through all Python files in the base path
    Dir.glob("#{base_path}/**/*.py") do |path|
      next if File.directory?(path)
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        lines = file.each_line.to_a
        next unless lines.any?(&.includes?("flask"))
        lines.each_with_index do |line, index|
          line = line.gsub(" ", "")
          # Identify Flask instance assignments
          match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask\.)?Flask\(/
          if !match.nil?
            flask_instance_name = match[1]
            flask_instance_map[flask_instance_name] ||= ""
          end

          # Identify Blueprint instance assignments
          match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask\.)?Blueprint\(/
          if !match.nil?
            prefix = ""
            blueprint_instance_name = match[1]
            param_codes = line.split("Blueprint", 2)[1]
            prefix_match = param_codes.match /url_prefix=['"]([^'"]*)['"]/
            if !prefix_match.nil? && prefix_match.size == 2
              prefix = prefix_match[1]
            end

            blueprint_prefix_map[blueprint_instance_name] ||= prefix
          end

          # Api from flask instance
          flask_instance_map.each do |_flask_instance_name, _prefix|
            match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask_restx\.)?Api\((app=)?#{_flask_instance_name}/
            if !match.nil?
              api_instance_name = match[1]
              api_instance_map[api_instance_name] ||= _prefix
            end
          end

          # Api from blueprint instance
          blueprint_prefix_map.each do |_blueprint_instance_name, _prefix|
            match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:flask_restx\.)?Api\((app=)?#{_blueprint_instance_name}/
            if !match.nil?
              api_instance_name = match[1]
              api_instance_map[api_instance_name] ||= _prefix
            end
          end

          # Api Namespace
          api_instance_map.each do |api_instance_name, _prefix|
            match = line.match /(#{api_instance_name})\.add_namespace\((#{PYTHON_VAR_NAME_REGEX})/
            if !match.nil?
              parser = get_parser(path)
              if parser.@global_variables.has_key?(match[2])
                gv = parser.@global_variables[match[2]]
                if gv.type == "Namespace"
                  namespace = gv.value.split("Namespace(", 2)[1]
                  if namespace.includes?("path=")
                    namespace = namespace.split("path=")[1].split(")")[0].split(",")[0]
                  else
                    namespace = namespace.split(",")[0].split(")")[0].strip
                  end

                  if (namespace.starts_with?("'") || namespace.starts_with?('"')) && namespace[0] == namespace[-1]
                    namespace = namespace[1..-2]
                    flask_instance_map[gv.name] = File.join(_prefix, namespace)
                  end
                end
              end
            end
          end

          # Temporary Addition: register_view
          blueprint_prefix_map.each do |blueprint_name, blueprint_prefix|
            register_views_match = line.match /#{blueprint_name},routes=(.*)\)/
            if !register_views_match.nil?
              route_paths = register_views_match[1]
              route_paths.scan /['"]([^'"]*)['"]/ do |path_str_match|
                if !path_str_match.nil? && path_str_match.size == 2
                  route_path = path_str_match[1]
                  # Parse methods from reference views (TODO)
                  route_url = "#{blueprint_prefix}#{route_path}"
                  route_url = "/#{route_url}" unless route_url.starts_with?("/")
                  details = Details.new(PathInfo.new(path, index + 1))
                  result << Endpoint.new(route_url, "GET", details)
                end
              end
            end
          end

          # Identify Flask route decorators
          line.scan(/@(#{PYTHON_VAR_NAME_REGEX})\.route\([rf]?['"]([^'"]*)['"](.*)/) do |_match|
            if _match.size > 0
              variable_name = _match[1]
              route_path = _match[2]
              extra_params = _match[3]
              router_info = Tuple(Int32, String, String, String).new(index, path, route_path, extra_params)
              ROUTER_MAP[variable_name] ||= [] of Tuple(Int32, String, String, String)
              ROUTER_MAP[variable_name] << router_info
            end
          end
        end
      end
    end

    # For each Flask instance, parse the routes
    flask_instance_map = flask_instance_map.merge(api_instance_map)
    flask_instance_map.each do |flask_instance_name, prefix|
      if ROUTER_MAP.has_key?(flask_instance_name)
        ROUTER_MAP[flask_instance_name].each do |router_info|
          line_index, path, route_path, extra_params = router_info
          lines = fetch_file_content(path).lines
          expect_params, next_line_index = extract_params_from_decorator(path, lines, line_index)

          is_class_router = false
          indent = lines[line_index].index("def") || 0
          unless lines[next_line_index].lstrip.starts_with?("def ")
            if lines[next_line_index].lstrip.starts_with?("class ")
              indent = lines[line_index].index("class") || 0
              is_class_router = true
            else
              next # Skip if not a function and not a class
            end
          end

          next_line_index += 1
          function_name_locations = Array(Tuple(Int32, String)).new
          while next_line_index < lines.size
            def_match = lines[next_line_index].match /(\s*)def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
            if def_match
              # Stop when the indentation is less than or equal to the class indentation
              break if is_class_router && def_match[1].size <= indent

              # Stop when the first function is found
              function_name_locations << Tuple.new(next_line_index, def_match[2])
              break unless is_class_router
            end

            # Stop when the next class definition is found
            if is_class_router
              class_match = lines[next_line_index].match /(\s*)class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*/
              if class_match
                break if class_match[1].size <= indent
              end
            end

            next_line_index += 1
          end

          function_name_locations.each do |_line_index, function_name|
            if is_class_router
              # Replace the class expect params with the function expect params
              def_expect_params, _ = extract_params_from_decorator(path, lines, _line_index, :up)
              if def_expect_params.size > 0
                expect_params = def_expect_params
              end
            end

            codeblock = parse_code_block(lines[_line_index..])
            next if codeblock.nil?
            codeblock_lines = codeblock.split("\n")

            # Get the HTTP method from the function name when it is not specified in the route decorator
            method = HTTP_METHODS.find { |http_method| function_name.downcase == http_method.downcase } || "GET"
            get_endpoints(method, route_path, extra_params, codeblock_lines, prefix).each do |endpoint|
              details = Details.new(PathInfo.new(path, _line_index + 1))
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
    end

    Fiber.yield
    result
  end

  # Fetch content of a file and cache it
  private def fetch_file_content(path : String) : String
    FILE_CONTENT_CACHE[path] ||= File.read(path, encoding: "utf-8", invalid: :skip)
  end

  # Create a Python parser for a given path and content
  def create_parser(path : String, content : String = "") : PythonParser
    content = fetch_file_content(path) if content.empty?
    lexer = PythonLexer.new
    tokens = lexer.tokenize(content)
    PythonParser.new(path, tokens, PARSER_MAP)
  end

  # Get a parser for a given path
  def get_parser(path : String, content : String = "") : PythonParser
    PARSER_MAP[path] ||= create_parser(path, content)
    PARSER_MAP[path]
  end

  # Extracts endpoint information from the given route and code block
  def get_endpoints(method : String, route_path : String, extra_params : String, codeblock_lines : Array(String), prefix : String)
    endpoints = [] of Endpoint
    methods = [] of String
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

    json_variable_names = [] of String
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
      REQUEST_PARAM_FIELD_MAP.each do |field_name, tuple|
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
      if !prefix.ends_with?("/") && !route_path.starts_with?("/")
        prefix = "#{prefix}/"
      end

      route_url = "#{prefix}#{route_path}"
      route_url = "/#{route_url}" unless route_url.starts_with?("/")

      params = get_filtered_params(http_method_name, suspicious_params)
      endpoints << Endpoint.new(route_url, http_method_name, params)
    end

    endpoints
  end

  # Filters the parameters based on the HTTP method
  def get_filtered_params(method : String, params : Array(Param)) : Array(Param)
    # Split to other module (duplicated method with analyzer_django)
    filtered_params = Array(Param).new
    upper_method = method.upcase

    params.each do |param|
      is_support_param = false
      support_methods = REQUEST_PARAM_TYPE_MAP.fetch(param.param_type, nil)
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
  def extract_params_from_decorator(path : String, lines : Array(String), line_index : Int32, direction : Symbol = :down) : Tuple(Array(Param), Int32)
    params = [] of Param
    codeline_index = (direction == :down) ? line_index + 1 : line_index - 1

    # Iterate through the lines until the decorator ends
    while (direction == :down && codeline_index < lines.size) || (direction == :up && codeline_index >= 0)
      decorator_match = lines[codeline_index].match /\s*@/
      break if decorator_match.nil?

      # Extract parameters from the expect decorator
      # https://flask-restx.readthedocs.io/en/latest/swagger.html#the-api-expect-decorator
      expect_match = lines[codeline_index].match /\s*@.+\.expect\(\s*(#{PYTHON_VAR_NAME_REGEX})/
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

    return params, codeline_index
  end
end

# Analyzer function for Flask
def analyzer_python_flask(options : Hash(String, String))
  instance = AnalyzerFlask.new(options)
  instance.analyze
end
