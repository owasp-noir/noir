require "../../models/analyzer"
require "./analyzer_python"

class AnalyzerFastAPI < AnalyzerPython
  @fastapi_base_path : String = ""

  def analyze
    include_router_map = {} of String => Hash(String, Router)
    fastapi_base_file : String = ""

    begin
      Dir.glob("#{base_path}/**/*.py") do |path|
        next if File.directory?(path)
        source = File.read(path, encoding: "utf-8", invalid: :skip)

        source.each_line do |line|
          match = line.match /(#{REGEX_PYTHON_VARIABLE_NAME})\s*=\s*FastAPI\s*\(/
          if !match.nil?
            fastapi_instance_name = match[1]
            if !include_router_map.has_key? fastapi_instance_name
              include_router_map[path] = {match[1] => Router.new("")}

              # base path
              fastapi_base_file = path
              @fastapi_base_path = Path.new(File.dirname(path)).parent.to_s
              break
            end
          end

          # https://fastapi.tiangolo.com/tutorial/bigger-applications/
          match = line.match /(#{REGEX_PYTHON_VARIABLE_NAME})\s*=\s*APIRouter\s*\(/
          if !match.nil?
            prefix = ""
            router_instance_name = match[1]
            param_codes = line.split("APIRouter", 2)[1]
            prefix_match = param_codes.match /prefix\s*=\s*['"]([^'"]*)['"]/
            if !prefix_match.nil? && prefix_match.size == 2
              prefix = prefix_match[1]
            end

            if include_router_map.has_key? path
              include_router_map[path][router_instance_name] = Router.new(prefix)
            else
              include_router_map[path] = {router_instance_name => Router.new(prefix)}
            end
          end
        end
      end
    rescue e
      logger.debug e
    end

    begin
      configure_router_prefix(fastapi_base_file, include_router_map)

      include_router_map.each do |path, router_map|
        source = File.read(path, encoding: "utf-8", invalid: :skip)
        import_modules = find_imported_modules(@fastapi_base_path, path, source)
        codelines = source.split("\n")
        router_map.each do |instance_name, router_class|
          codelines.each_with_index do |line, index|
            line.scan(/@#{instance_name}\.([a-zA-Z]+)\([rf]?['"]([^'"]*)['"](.*)/) do |match|
              if match.size > 0
                http_method_name = match[1].downcase
                if ["websocket", "route", "api_route"].includes?(http_method_name)
                  http_method_name = "GET"
                elsif !HTTP_METHOD_NAMES.includes?(http_method_name)
                  next
                end

                http_method_name = http_method_name.upcase

                http_route_path = match[2]
                _extra_params = match[3]
                params = [] of Param

                # Get path params from route path
                query_params = [] of String
                http_route_path.scan(/\{(#{REGEX_PYTHON_VARIABLE_NAME})\}/) do |route_match|
                  if route_match.size > 0
                    query_params << route_match[1]
                  end
                end

                # Parsing extra params
                function_definition = parse_function_definition(codelines, index + 1)
                if !function_definition.nil?
                  function_params = function_definition.params
                  if function_params.size > 0
                    function_params.each do |param|
                      # https://fastapi.tiangolo.com/tutorial/path-params-numeric-validations/#order-the-parameters-as-you-need-tricks
                      if param.name == "*"
                        next
                      end

                      if !query_params.includes? param.name
                        # Default value is numeric or string only
                        default_value = return_literal_value(param.default)

                        # Get param type by default value first
                        if param.default.size != 0
                          param_type = infer_parameter_type(param.default)
                        end

                        # Get param type by type if not found
                        if param_type.nil?
                          if param.type.size != 0
                            param_type = param.type
                            # https://peps.python.org/pep-0593/
                            if param_type.includes?("Annotated[")
                              param_type = param_type.split("Annotated[", 2)[-1].split(",", 2)[-1]
                            end

                            # https://peps.python.org/pep-0484/#union-types
                            if param_type.includes?("Union[")
                              param_type = param_type.split("Union[", 2)[-1]
                            end

                            param_type = infer_parameter_type(param_type, true)
                            if param_type.nil?
                              if param.type.size == 0
                                param_type = "query"
                              end
                            end
                          else
                            param_type = "query"
                          end
                        end

                        if param_type.nil?
                          if /^#{REGEX_PYTHON_VARIABLE_NAME}$/.match(param.type)
                            new_params = nil
                            if param.type == "Request" || param.type == "dict"
                              function_codeblock = parse_function_or_class(codelines[index + 1..])
                              next if function_codeblock.nil?
                              new_params = find_dictionary_params(function_codeblock, param)
                            elsif import_modules.has_key? param.type
                              # Parse model class from module path
                              import_module_path = import_modules[param.type].first

                              # Skip if import module path is not identified
                              if import_module_path.size == 0
                                next
                              end

                              import_module_source = File.read(import_module_path, encoding: "utf-8", invalid: :skip)
                              new_params = find_base_model_params(import_module_source, param.type, param.name)
                            else
                              # Parse cmodel class from current source
                              new_params = find_base_model_params(source, param.type, param.name)
                            end

                            if new_params.nil?
                              next
                            end

                            new_params.each do |model_param|
                              params << model_param
                            end
                          end
                        else
                          # Add endpoint param
                          params << Param.new(param.name, default_value, param_type)
                        end
                      end
                    end
                  end
                end

                result << Endpoint.new(router_class.join(http_route_path), http_method_name, params)
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
    end
    Fiber.yield

    result
  end

  def configure_router_prefix(file : String, include_router_map : Hash, router_prefix : String = "")
    if file.size == 0 || !File.exists?(file)
      return
    end

    # https://fastapi.tiangolo.com/tutorial/bigger-applications/
    source = File.read(file, encoding: "utf-8", invalid: :skip)
    import_modules = find_imported_modules(@fastapi_base_path, file, source)
    include_router_map[file].each do |instance_name, router_class|
      router_class.prefix = router_prefix

      # Parse '{app}.include_router({item}.router, prefix="{prefix}")' code
      # and regist prefix to 'include_router_map' variable
      source.scan(/#{instance_name}\.include_router\(([^\)]*)\)/).each do |match|
        if match.size > 0
          params = match[1].split(",")
          prefix = ""
          router_instance_name = params[0].strip
          if params.size != 1
            select_params = params.select(&.strip.starts_with?("prefix"))
            if select_params.size != 0
              prefix = select_params.first.split("=")[1]
              if prefix.count("\"") == 2
                prefix = prefix.split("\"")[1].split("\"")[0]
              elsif prefix.count("'") == 2
                prefix = prefix.split("'")[1].split("'")[0]
              end
            end
          end

          # Regist router's prefix recursivly
          prefix = router_class.join(prefix)
          if router_instance_name.count(".") == 0
            next if !import_modules.has_key? router_instance_name
            import_module_path = import_modules[router_instance_name].first

            next if !include_router_map.has_key? import_module_path
            configure_router_prefix(import_module_path, include_router_map, prefix)
          elsif router_instance_name.count(".") == 1
            module_name, _router_instance_name = router_instance_name.split(".")
            next if !import_modules.has_key? module_name
            import_module_path = import_modules[module_name].first

            next if !include_router_map.has_key? import_module_path
            configure_router_prefix(import_module_path, include_router_map, prefix)
          end
        end
      end
    end
  end

  def infer_parameter_type(data, is_param_type = false) : String | Nil
    # https://github.com/tiangolo/fastapi/blob/master/fastapi/params.py
    if data.match(/(\b)*Cookie(\b)*/)
      "cookie"
    elsif data.match(/(\b)*Header(\b)*/) != nil
      "header"
    elsif data.match(/(\b)*Body(\b)*/) || data.match(/(\b)*Form(\b)*/) ||
          data.match(/(\b)*File(\b)*/) || data.match(/(\b)*UploadFile(\b)*/)
      "form"
    elsif data.match(/(\b)*Query(\b)*/)
      "query"
    elsif data.match(/(\b)*WebSocket(\b)*/)
      "websocket"
    elsif is_param_type
      # default variable type
      ["str", "int", "float", "bool", "EmailStr"].each do |type|
        if data.index(type) != nil
          return "query"
        end
      end
    end
  end

  def find_base_model_params(source : String, class_name : String, param_name : String) : Array(Param)
    params = [] of Param
    class_codeblock = parse_function_or_class(source, /\s*class\s*#{class_name}\s*\(/)
    if class_codeblock.nil?
      return params
    end

    # https://fastapi.tiangolo.com/tutorial/body/#import-pydantics-basemodel
    class_codeblock.split("\n").each_with_index do |line, index|
      if index == 0
        param_code = line.split("(", 2)[-1].split(")")[0]
        if param_code.match(/(\b)*str,\s*(enum\.){0,1}Enum(\b)*/)
          return [Param.new(param_name.strip, "", "query")]
        end
        if /^#{REGEX_PYTHON_VARIABLE_NAME}$/.match(param_code) == nil
          return params
        end
      else
        if line.split(":").size != 2
          break
        end

        param_name, extra = line.split(":", 2)
        param_type = ""
        param_default = ""
        param_type_and_default = extra.split("=", 2)
        if param_type_and_default.size == 2
          param_type, param_default = param_type_and_default
        else
          param_type = param_type_and_default[0]
        end

        if param_name.size != 0 && param_type.size != 0
          default_value = return_literal_value(param_default.strip)
          params << Param.new(param_name.strip, default_value, "form")
        end
      end
    end

    params
  end

  def find_dictionary_params(source : String, param : FunctionParameter) : Array(Param)
    new_params = [] of Param
    json_variable_names = [] of String
    codelines = source.split("\n")
    if param.type == "Request"
      # Parse JSON variable names
      codelines.each do |codeline|
        match = codeline.match /(#{REGEX_PYTHON_VARIABLE_NAME}).*=\s*(await\s*){0,1}#{param.name}.json\(\)/
        if !match.nil? && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
      end

      new_params = find_json_params(codelines, json_variable_names)
    elsif param.type == "dict"
      json_variable_names << param.name
      new_params = find_json_params(codelines, json_variable_names)
    end

    new_params
  end
end

class Router
  def initialize(prefix : String)
    @prefix = prefix
  end

  def prefix
    @prefix
  end

  def join(url : String) : String
    if prefix.ends_with?("/") && url.starts_with?("/")
      url = url[1..]
    elsif !prefix.ends_with?("/") && !url.starts_with?("/")
      url = "/#{url}"
    end

    @prefix + url
  end

  def prefix=(new_prefix : String)
    @prefix = new_prefix
  end
end

def analyzer_fastapi(options : Hash(Symbol, String))
  instance = AnalyzerFastAPI.new(options)
  instance.analyze
end

class String
  def numeric?
    self.to_f != nil rescue false
  end
end
