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
  PARSER_MAP = Hash(String, PythonParser).new

  def analyze
    flask_instance_map = Hash(String, String).new
    blueprint_prefix_map = Hash(String, String).new
    api_instance_map = Hash(String, String).new

    begin
      # Iterate through all Python files in the base path
      Dir.glob("#{base_path}/**/*.py") do |path|
        next if File.directory?(path)

        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          file.each_line.with_index do |line, index|
            # Identify Flask instance assignments
            match = line.match /(#{PYTHON_VAR_NAME_REGEX})\s*(?::\s*#{PYTHON_VAR_NAME_REGEX})?\s*=\s*Flask\s*\(/
            if !match.nil?
              flask_instance_name = match[1]
              flask_instance_map[flask_instance_name] ||= ""
            end

            # Common flask instance name
            flask_instance_map["app"] ||= ""

            # Identify Blueprint instance assignments
            match = line.match /(#{PYTHON_VAR_NAME_REGEX})\s*(?::\s*#{PYTHON_VAR_NAME_REGEX})?\s*=\s*Blueprint\s*\(/
            if !match.nil?
              prefix = ""
              blueprint_instance_name = match[1]
              param_codes = line.split("Blueprint", 2)[1]
              prefix_match = param_codes.match /url_prefix\s*=\s*['"]([^'"]*)['"]/
              if !prefix_match.nil? && prefix_match.size == 2
                prefix = prefix_match[1]
              end

              blueprint_prefix_map[blueprint_instance_name] ||= prefix
            end

            # Api Blueprint
            blueprint_prefix_map.each do |blueprint_instance_name, prefix|
              match = line.match /(#{PYTHON_VAR_NAME_REGEX})\s*(?::\s*#{PYTHON_VAR_NAME_REGEX})?\s*=\s*(flask_restx.)?Api\s*\(\s*#{blueprint_instance_name}/
              if !match.nil?
                api_instance_name = match[1]
                api_instance_map[api_instance_name] ||= prefix
              end
            end

            # Api Namespace
            api_instance_map.each do |api_instance_name, prefix|
              match = line.match /(#{api_instance_name})\.add_namespace\s*\(\s*(#{PYTHON_VAR_NAME_REGEX})/
              if !match.nil?
                parser = get_parser(path)
                if parser.@global_variables.has_key?(match[2])
                  gv = parser.@global_variables[match[2]]
                  if gv.type == "Namespace"
                    namespace = gv.value.split("Namespace(", 2)[1].split(",")[0].split(")")[0].strip
                    if (namespace.starts_with?("'") || namespace.starts_with?('"')) && namespace[0] == namespace[-1]
                      namespace = namespace[1..-2]
                      flask_instance_map[gv.name] = File.join(prefix, namespace)
                    end
                  end
                end
              end
            end

            # Temporary Addition: register_view
            blueprint_prefix_map.each do |blueprint_name, blueprint_prefix|
              register_views_match = line.match /#{blueprint_name},\s*routes\s*=\s*(.*)\)/
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
          end
        end
      end
    rescue e : Exception
      puts e.message
    end

    begin
      # Process each Python file in the base path
      Dir.glob("#{base_path}/**/*.py") do |path|
        next if File.directory?(path)
        source = File.read(path, encoding: "utf-8", invalid: :skip)
        lines = source.split "\n"

        line_index = 0
        while line_index < lines.size
          line = lines[line_index]
          flask_instance_map.each do |flask_instance_name, prefix|
            # Identify Flask route decorators
            line.scan(/@#{flask_instance_name}\.route\([rf]?['"]([^'"]*)['"](.*)/) do |match|
              if match.size > 0
                route_path = match[1]
                extra_params = match[2]

                # Skip decorator lines
                codeline_index = line_index
                while codeline_index < lines.size
                  decorator_match = lines[codeline_index].match /\s*@/
                  if !decorator_match.nil?
                    codeline_index += 1
                    next
                  end
                  break
                end

                codeblock = parse_code_block(lines[codeline_index..].join("\n"))
                next if codeblock.nil?
                codeblock_lines = codeblock.split("\n")[1..]

                get_endpoints(route_path, extra_params, codeblock_lines, prefix).each do |endpoint|
                  details = Details.new(PathInfo.new(path, line_index + 1))
                  endpoint.set_details(details)
                  result << endpoint
                end
              end
            end
          end
          line_index += 1
        end
      end
    rescue e : Exception
      logger.debug e.message
    end
    Fiber.yield

    result
  end

  # Fetch content of a file and cache it
  private def fetch_file_content(path : String) : String
    FILE_CONTENT_CACHE[path] ||= File.read(path, encoding: "utf-8", invalid: :skip)
  end
  
  # Create a Kotlin parser for a given path and content
  def create_parser(path : String, content : String = "") : PythonParser
    content = fetch_file_content(path) if content.empty?
    lexer = PythonLexer.new
    tokens = lexer.tokenize(content)
    PythonParser.new(path, tokens, PARSER_MAP)
  end

  # Get a parser for a given path
  def get_parser(path : String, content : String = "") : PythonParser
    PARSER_MAP[path] ||= create_parser(path, content)
    return PARSER_MAP[path]
  end  

  # Extracts endpoint information from the given route and code block
  def get_endpoints(route_path : String, extra_params : String, codeblock_lines : Array(String), prefix : String)
    endpoints = [] of Endpoint
    suspicious_http_methods = [] of String
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
          suspicious_http_methods << method_name.upcase
        end
      end
    else
      suspicious_http_methods << "GET"
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

    suspicious_http_methods.uniq.each do |http_method_name|
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
end

# Analyzer function for Flask
def analyzer_python_flask(options : Hash(String, String))
  instance = AnalyzerFlask.new(options)
  instance.analyze
end
