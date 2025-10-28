require "../../../models/analyzer"
require "./python"

module Analyzer::Python
  class FastAPI < Python
    @fastapi_base_path : ::String = ""

    def analyze
      include_router_map = Hash(::String, Hash(::String, Router)).new
      fastapi_base_file : ::String = ""

      begin
        # Iterate through all Python files in all base paths
        base_paths.each do |current_base_path|
          Dir.glob("#{current_base_path}/**/*.py") do |path|
            next if File.directory?(path)
            next if path.includes?("/site-packages/")
            source = File.read(path, encoding: "utf-8", invalid: :skip)

            source.each_line do |line|
              line = line.gsub(" ", "")
              match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:fastapi\.)?FastAPI\(/
              if !match.nil?
                fastapi_instance_name = match[1]
                unless include_router_map.has_key?(fastapi_instance_name)
                  include_router_map[path] = {match[1] => Router.new("")}

                  # base path
                  fastapi_base_file = path
                  @fastapi_base_path = Path.new(File.dirname(path)).parent.to_s
                  break
                end
              end

              # https://fastapi.tiangolo.com/tutorial/bigger-applications/
              match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:fastapi\.)?APIRouter\(/
              if !match.nil?
                prefix = ""
                router_instance_name = match[1]
                param_codes = line.split("APIRouter", 2)[1]
                prefix_match = param_codes.match /prefix\s*=\s*['"]([^'"]*)['"]/
                if !prefix_match.nil? && prefix_match.size == 2
                  prefix = prefix_match[1]
                end

                if include_router_map.has_key?(path)
                  include_router_map[path][router_instance_name] = Router.new(prefix)
                else
                  include_router_map[path] = {router_instance_name => Router.new(prefix)}
                end
              end
            end
          end
        end
      rescue e : Exception
        logger.debug e.message
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
                  elsif !HTTP_METHODS.includes?(http_method_name)
                    next
                  end

                  http_method_name = http_method_name.upcase

                  http_route_path = match[2]
                  _extra_params = match[3]
                  params = [] of Param

                  # Get path params from route path
                  query_params = [] of ::String
                  http_route_path.scan(/\{(#{PYTHON_VAR_NAME_REGEX})\}/) do |route_match|
                    if route_match.size > 0
                      query_params << route_match[1]
                    end
                  end

                  # Parsing extra params
                  function_definition = parse_function_def(codelines, index + 1)
                  if !function_definition.nil?
                    function_params = function_definition.params
                    if function_params.size > 0
                      function_params.each do |param|
                        # https://fastapi.tiangolo.com/tutorial/path-params-numeric-validations/#order-the-parameters-as-you-need-tricks
                        next if param.name == "*"

                        unless query_params.includes?(param.name)
                          # Default value is numeric or string only
                          default_value = return_literal_value(param.default)

                          # Get param type by default value first
                          param_type = infer_parameter_type(param.default) unless param.default.empty?

                          # Get param type by type if not found
                          if param_type.nil? && !param.type.empty?
                            param_type = param.type
                            # https://peps.python.org/pep-0593/
                            param_type = param_type.split("Annotated[", 2)[-1].split(",", 2)[-1] if param_type.includes?("Annotated[")

                            # https://peps.python.org/pep-0484/#union-types
                            param_type = param_type.split("Union[", 2)[-1] if param_type.includes?("Union[")

                            param_type = infer_parameter_type(param_type, true)
                            param_type = "query" if param_type.nil? && param.type.empty?
                          else
                            param_type = "query" if param_type.nil?
                          end

                          if param_type.nil?
                            if /^#{PYTHON_VAR_NAME_REGEX}$/.match(param.type)
                              new_params = nil
                              if ["Request", "dict"].includes?(param.type)
                                function_codeblock = parse_code_block(codelines[index + 1..])
                                next if function_codeblock.nil?
                                new_params = find_dictionary_params(function_codeblock, param)
                              elsif import_modules.has_key?(param.type)
                                # Parse model class from module path
                                import_module_path = import_modules[param.type].first

                                # Skip if import module path is not identified
                                next if import_module_path.empty?

                                import_module_source = File.read(import_module_path, encoding: "utf-8", invalid: :skip)
                                new_params = find_base_model_params(import_module_source, param.type, param.name)
                              else
                                # Parse model class from current source
                                new_params = find_base_model_params(source, param.type, param.name)
                              end

                              next if new_params.nil?

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

                  details = Details.new(PathInfo.new(path, index + 1))
                  result << Endpoint.new(router_class.join(http_route_path), http_method_name, params, details)
                end
              end
            end
          end
        rescue e : Exception
          logger.debug e.message
        end
      end
      Fiber.yield

      result
    end

    # Configures the prefix for each router
    def configure_router_prefix(file : ::String, include_router_map : Hash(::String, Hash(::String, Router)), router_prefix : ::String = "")
      return if file.empty? || !File.exists?(file)

      # Parse the source file for router configuration
      source = File.read(file, encoding: "utf-8", invalid: :skip)
      import_modules = find_imported_modules(@fastapi_base_path, file, source)
      include_router_map[file].each do |instance_name, router_class|
        router_class.prefix = router_prefix

        # Parse '{app}.include_router({item}.router, prefix="{prefix}")' code
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

            # Register router's prefix recursively
            prefix = router_class.join(prefix)
            if router_instance_name.count(".") == 0
              next unless import_modules.has_key?(router_instance_name)
              import_module_path = import_modules[router_instance_name].first

              next unless include_router_map.has_key?(import_module_path)
              configure_router_prefix(import_module_path, include_router_map, prefix)
            elsif router_instance_name.count(".") == 1
              module_name, _router_instance_name = router_instance_name.split(".")
              next unless import_modules.has_key?(module_name)
              import_module_path = import_modules[module_name].first

              next unless include_router_map.has_key?(import_module_path)
              configure_router_prefix(import_module_path, include_router_map, prefix)
            end
          end
        end
      end
    end

    # Infers the type of the parameter based on its default value or type annotation
    def infer_parameter_type(data : ::String, is_param_type = false) : ::String | Nil
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
          return "query" if data.includes?(type)
        end
      end
    end

    # Finds the parameters for a base model class
    def find_base_model_params(source : ::String, class_name : ::String, param_name : ::String) : Array(Param)
      params = [] of Param
      class_codeblock = parse_code_block(source, /\s*class\s*#{class_name}\s*\(/)
      return params if class_codeblock.nil?

      # Parse the class code block to extract parameters
      class_codeblock.split("\n").each_with_index do |line, index|
        if index == 0
          param_code = line.split("(", 2)[-1].split(")")[0]
          if param_code.match(/(\b)*str,\s*(enum\.){0,1}Enum(\b)*/)
            return [Param.new(param_name.strip, "", "query")]
          end
          return params unless /^#{PYTHON_VAR_NAME_REGEX}$/.match(param_code)
        else
          break unless line.split(":").size == 2

          param_name, extra = line.split(":", 2)
          param_type = ""
          param_default = ""
          param_type_and_default = extra.split("=", 2)
          if param_type_and_default.size == 2
            param_type, param_default = param_type_and_default
          else
            param_type = param_type_and_default[0]
          end

          if !param_name.empty? && !param_type.empty?
            default_value = return_literal_value(param_default.strip)
            params << Param.new(param_name.strip, default_value, "form")
          end
        end
      end

      params
    end

    # Finds parameters in dictionary structures
    def find_dictionary_params(source : ::String, param : FunctionParameter) : Array(Param)
      new_params = [] of Param
      json_variable_names = [] of ::String
      codelines = source.split("\n")
      if param.type == "Request"
        # Parse JSON variable names
        codelines.each do |codeline|
          match = codeline.match /(#{PYTHON_VAR_NAME_REGEX})\s*(?::\s*#{PYTHON_VAR_NAME_REGEX})?\s*=\s*(await\s*){0,1}#{param.name}.json\(\)/
          json_variable_names << match[1] if !match.nil? && !json_variable_names.includes?(match[1])
        end

        new_params = find_json_params(codelines, json_variable_names)
      elsif param.type == "dict"
        json_variable_names << param.name
        new_params = find_json_params(codelines, json_variable_names)
      end

      new_params
    end
  end

  # Router class for handling URL prefix joining
  class Router
    @prefix : ::String

    def initialize(prefix : ::String)
      @prefix = prefix
    end

    def prefix
      @prefix
    end

    def join(url : ::String) : ::String
      url = url[1..] if prefix.ends_with?("/") && url.starts_with?("/")
      url = "/#{url}" unless prefix.ends_with?("/") || url.starts_with?("/")

      @prefix + url
    end

    def prefix=(new_prefix : ::String)
      @prefix = new_prefix
    end
  end

  # Extend ::String class to check if a string is numeric
  class ::String
    def numeric?
      self.to_f != nil rescue false
    end
  end
end
