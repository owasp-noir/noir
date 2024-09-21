require "../../../models/analyzer"
require "../../../minilexers/java"
require "../../../miniparsers/java"

module Analyzer::Java
  class Spring < Analyzer
    REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
    REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/
    FILE_CONTENT_CACHE      = Hash(String, String).new

    def analyze
      parser_map = Hash(String, JavaParser).new
      package_map = Hash(String, Hash(String, ClassModel)).new
      webflux_base_path_map = Hash(String, String).new

      Dir.glob("#{@base_path}/**/*") do |path|
        url = ""

        # Extract the Webflux base path from 'application.yml' in specified directories
        if File.directory?(path)
          if path.ends_with?("/src")
            application_yml_path = File.join(path, "main/resources/application.yml")
            if File.exists?(application_yml_path)
              begin
                config = YAML.parse(File.read(application_yml_path))
                spring = config["spring"]
                webflux = spring["webflux"]
                webflux_base_path = webflux["base-path"]

                if webflux_base_path
                  webflux_base_path_map[path] = webflux_base_path.as_s
                end
              rescue e
                # Handle parsing errors if necessary
              end
            end

            application_properties_path = File.join(path, "main/resources/application.properties")
            if File.exists?(application_properties_path)
              begin
                properties = File.read(application_properties_path)
                base_path = properties.match(/spring\.webflux\.base-path\s*=\s*(.*)/)
                if base_path
                  webflux_base_path = base_path[1]
                  webflux_base_path_map[path] = webflux_base_path if webflux_base_path
                end
              rescue e
                # Handle parsing errors if necessary
              end
            end
          end
        elsif File.exists?(path) && path.ends_with?(".java")
          webflux_base_path = find_base_path(path, webflux_base_path_map)
          # Load Java file content into cache for processing
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          FILE_CONTENT_CACHE[path] = content

          # Process files that include Spring MVC bindings for routing
          spring_web_bind_package = "org.springframework.web.bind.annotation."
          has_spring_bindings = content.includes?(spring_web_bind_package)
          if has_spring_bindings
            if parser_map.has_key?(path)
              parser = parser_map[path]
              tokens = parser.tokens
            else
              parser = create_parser(Path.new(path), content)
              tokens = parser.tokens
              parser_map[path] = parser
            end

            package_name = parser.get_package_name(tokens)
            next if package_name == ""
            root_source_directory : Path = parser.get_root_source_directory(path, package_name)
            package_directory = Path.new(path).dirname

            # Import packages
            import_map = Hash(String, ClassModel).new
            parser.import_statements.each do |import_statement|
              import_path = import_statement.gsub(".", "/")
              if import_path.ends_with?("/*")
                import_directory = root_source_directory.join(import_path[..-3])
                if Dir.exists?(import_directory)
                  Dir.glob("#{import_directory}/*.java") do |_path|
                    next if path == _path
                    if !parser_map.has_key?(_path)
                      _parser = create_parser(Path.new(_path))
                      parser_map[_path] = _parser
                    else
                      _parser = parser_map[_path]
                    end

                    _parser.classes.each do |package_class|
                      import_map[package_class.name] = package_class
                    end
                  end
                end
              else
                source_path = root_source_directory.join(import_path + ".java")
                next if source_path.dirname == package_directory || !File.exists?(source_path)
                if !parser_map.has_key?(source_path.to_s)
                  _parser = create_parser(source_path)
                  parser_map[source_path.to_s] = _parser
                  _parser.classes.each do |package_class|
                    import_map[package_class.name] = package_class
                  end
                else
                  _parser = parser_map[source_path.to_s]
                  _parser.classes.each do |package_class|
                    import_map[package_class.name] = package_class
                  end
                end
              end
            end

            # Import packages from the same directory
            package_class_map = package_map[package_directory]?
            if package_class_map.nil?
              package_class_map = Hash(String, ClassModel).new
              Dir.glob("#{package_directory}/*.java") do |_path|
                next if path == _path
                if !parser_map.has_key?(_path)
                  _parser = create_parser(Path.new(_path))
                  parser_map[_path] = _parser
                else
                  _parser = parser_map[_path]
                end

                _parser.classes.each do |package_class|
                  package_class_map[package_class.name] = package_class
                end

                parser.classes.each do |package_class|
                  package_class_map[package_class.name] = package_class
                end

                package_map[package_directory] = package_class_map
              end
            end

            # Extract URL mappings and methods from Spring MVC annotated classes
            class_map = package_class_map.merge(import_map)
            parser.classes.each do |class_model|
              class_annotation = class_model.annotations["RequestMapping"]?
              if !class_annotation.nil?
                next if class_annotation.params.size == 0
                class_path_token = class_annotation.params[0][-1]
                if class_path_token.type == :STRING_LITERAL
                  url = class_path_token.value[1..-2]
                  if url.ends_with? "*"
                    url = url[0..-2]
                  end
                end
              end

              class_model.methods.values.each do |method|
                method.annotations.values.each do |method_annotation|
                  url_paths = Array(String).new

                  # Spring MVC method mappings
                  request_methods = Array(String).new
                  if method_annotation.name.ends_with? "Mapping"
                    parameter_format = nil
                    annotation_parameters = method_annotation.params
                    annotation_parameters.each do |annotation_parameter_tokens|
                      if annotation_parameter_tokens.size > 2
                        annotation_parameter_key = annotation_parameter_tokens[0].value
                        annotation_parameter_value = annotation_parameter_tokens[-1].value
                        if annotation_parameter_key == "method"
                          if ["}", "]"].includes?(annotation_parameter_value)
                            # Handle methods declared with multiple HTTP verbs
                            annotation_parameter_tokens.reverse_each do |token|
                              break if token.value == "method"
                              next if [:LBRACE, :RBRACE, :LBRACK, :RBRACK, :COMMA, :DOT].includes?(token.type)
                              http_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
                              if http_methods.includes?(token.value)
                                request_methods.push(token.value)
                              end
                            end
                          else
                            request_methods.push(annotation_parameter_value)
                          end
                        elsif annotation_parameter_key == "consumes"
                          # Set parameter format based on the 'consumes' attribute of the annotation.
                          if annotation_parameter_value.ends_with? "APPLICATION_FORM_URLENCODED_VALUE"
                            parameter_format = "form"
                          elsif annotation_parameter_value.ends_with? "APPLICATION_JSON_VALUE"
                            parameter_format = "json"
                          end
                        end
                      end
                    end

                    if webflux_base_path.ends_with?("/") && url.starts_with?("/")
                      webflux_base_path = webflux_base_path[..-2]
                    end

                    # Parse and construct endpoints for methods annotated with 'RequestMapping' or specific HTTP methods
                    if method_annotation.name == "RequestMapping"
                      url_paths = [""]
                      if method_annotation.params.size > 0
                        url_paths = get_mapping_path(parser, tokens, method_annotation.params)
                      end

                      line = method_annotation.tokens[0].line
                      details = Details.new(PathInfo.new(path, line))

                      if request_methods.empty?
                        # Handle default HTTP methods if no specific method is annotated
                        ["GET", "POST", "PUT", "DELETE", "PATCH"].each do |_request_method|
                          parameters = get_endpoint_parameters(parser, _request_method, method, parameter_format, class_map)
                          url_paths.each do |url_path|
                            @result << Endpoint.new("#{webflux_base_path}#{url}#{url_path}", _request_method, parameters, details)
                          end
                        end
                      else
                        # Create endpoints for annotated HTTP methods
                        url_paths.each do |url_path|
                          request_methods.each do |request_method|
                            parameters = get_endpoint_parameters(parser, request_method, method, parameter_format, class_map)
                            @result << Endpoint.new("#{webflux_base_path}#{url}#{url_path}", request_method, parameters, details)
                          end
                        end
                      end
                      break
                    else
                      # Handle other specific mapping annotations like 'GetMapping', 'PostMapping', etc
                      mapping_annotations = ["GetMapping", "PostMapping", "PutMapping", "DeleteMapping", "PatchMapping"]
                      mapping_index = mapping_annotations.index(method_annotation.name)
                      if !mapping_index.nil?
                        line = method_annotation.tokens[0].line
                        request_method = mapping_annotations[mapping_index][0..-8].upcase
                        if parameter_format.nil? && request_method == "POST"
                          parameter_format = "form"
                        end
                        parameters = get_endpoint_parameters(parser, request_method, method, parameter_format, class_map)

                        url_paths = [""]
                        if method_annotation.params.size > 0
                          url_paths = get_mapping_path(parser, tokens, method_annotation.params)
                        end

                        details = Details.new(PathInfo.new(path, line))
                        url_paths.each do |url_path|
                          @result << Endpoint.new("#{webflux_base_path}#{url}#{url_path}", request_method, parameters, details)
                        end
                        break
                      end
                    end
                  end
                end
              end
            end
          else
            # Extract and construct endpoints from reactive route configurations
            content.scan(REGEX_ROUTER_CODE_BLOCK) do |route_code|
              method_code = route_code[0]
              method_code.scan(REGEX_ROUTE_CODE_LINE) do |match|
                next if match.size != 4
                method = match[2]
                endpoint = match[3].gsub(/\n/, "")
                details = Details.new(PathInfo.new(path))
                @result << Endpoint.new("#{url}#{endpoint}", method, details)
              end
            end
          end
        end
      end
      Fiber.yield

      @result
    end

    def create_parser(path : Path, content : String = "")
      if content == ""
        if FILE_CONTENT_CACHE.has_key?(path.to_s)
          content = FILE_CONTENT_CACHE[path.to_s]
        else
          content = File.read(path, encoding: "utf-8", invalid: :skip)
        end
      end

      lexer = JavaLexer.new
      tokens = lexer.tokenize(content)
      parser = JavaParser.new(path.to_s, tokens)
      parser
    end

    def find_base_path(current_path : String, base_paths : Hash(String, String))
      base_paths.keys.sort_by!(&.size).reverse!.each do |path|
        if current_path.starts_with?(path)
          return base_paths[path]
        end
      end

      ""
    end

    def get_mapping_path(parser : JavaParser, tokens : Array(Token), method_params : Array(Array(Token)))
      # 1. Search for the value of the Mapping annotation.
      # 2. If the value is a string literal, return the literal.
      # 3. If the value is an array, return each element of the array.
      # 4. In other cases, return an empty array.
      url_paths = Array(String).new
      if method_params[0].size != 0
        path_argument_index = 0
        method_params.each_with_index do |mapping_parameter, index|
          if mapping_parameter[0].type == :IDENTIFIER && mapping_parameter[0].value == "value"
            path_argument_index = index
          end
        end

        path_parameter_tokens = method_params[path_argument_index]
        # Extract single and multiple mapping path
        if path_parameter_tokens[-1].type == :STRING_LITERAL
          url_paths << path_parameter_tokens[-1].value[1..-2]
        elsif path_parameter_tokens[-1].type == :RBRACE
          i = path_parameter_tokens.size - 2
          while i > 0
            parameter_token = path_parameter_tokens[i]
            if parameter_token.type == :LBRACE
              break
            elsif parameter_token.type == :COMMA
              i -= 1
              next
            elsif parameter_token.type == :STRING_LITERAL
              url_paths << parameter_token.value[1..-2]
            else
              break
            end

            i -= 1
          end
        end
      end

      url_paths
    end

    def get_endpoint_parameters(parser : JavaParser, request_method : String, method : MethodModel, parameter_format : String | Nil, package_class_map : Hash(String, ClassModel)) : Array(Param)
      endpoint_parameters = Array(Param).new
      method.params.each do |method_param_tokens|
        next if method_param_tokens.size == 0
        if method_param_tokens[-1].type == :IDENTIFIER
          if method_param_tokens[0].type == :AT
            if method_param_tokens[1].value == "PathVariable"
              next
            elsif method_param_tokens[1].value == "RequestBody"
              if parameter_format.nil?
                parameter_format = "json"
              end
            elsif method_param_tokens[1].value == "RequestParam"
              parameter_format = "query"
            elsif method_param_tokens[1].value == "RequestHeader"
              parameter_format = "header"
            end
          end

          if parameter_format.nil?
            parameter_format = "query"
          end

          default_value = nil
          # Extract parameter name directly if not an identifier
          parameter_name = method_param_tokens[-1].value
          if method_param_tokens.size > 2
            if method_param_tokens[2].type == :LPAREN
              request_parameters = parser.parse_formal_parameters(method_param_tokens, 2)
              request_parameters.each do |request_parameter_tokens|
                if request_parameter_tokens.size > 2
                  request_param_name = request_parameter_tokens[0].value
                  request_param_value = request_parameter_tokens[-1].value

                  # Extract 'name' from @RequestParam(value/defaultValue/name = "name")
                  if request_param_name == "value"
                    parameter_name = request_param_value[1..-2]
                  elsif request_param_name == "name"
                    parameter_name = request_param_value[1..-2]
                  elsif request_param_name == "defaultValue"
                    default_value = request_param_value[1..-2]
                  end
                end
              end
              # Handle direct string literal as parameter name, e.g., @RequestParam("name")
              if method_param_tokens[3].type == :STRING_LITERAL
                parameter_name_token = method_param_tokens[3]
                parameter_name = parameter_name_token.value[1..-2]
              end
            end
          end

          argument_name = method_param_tokens[-1].value
          parameter_type = method_param_tokens[-2].value
          if ["long", "int", "integer", "char", "boolean", "string", "multipartfile"].index(parameter_type.downcase)
            param_default_value = default_value.nil? ? "" : default_value
            endpoint_parameters << Param.new(parameter_name, param_default_value, parameter_format)
          elsif parameter_type == "HttpServletRequest"
            i = 0
            while i < method.body.size - 6
              if [:TAB, :NEWLINE].index(method.body[i].type)
                i += 1
                next
              end

              next if method.body[i].type == :NEWLINE

              if method.body[i].type == :IDENTIFIER && method.body[i].value == argument_name
                if method.body[i + 1].type == :DOT
                  if method.body[i + 2].type == :IDENTIFIER && method.body[i + 3].type == :LPAREN
                    servlet_request_method_name = method.body[i + 2].value
                    if method.body[i + 4].type == :STRING_LITERAL
                      parameter_name = method.body[i + 4].value[1..-2]
                      if servlet_request_method_name == "getParameter"
                        unless endpoint_parameters.any? { |param| param.name == parameter_name }
                          endpoint_parameters << Param.new(parameter_name, "", parameter_format)
                        end
                        i += 6
                        next
                      elsif servlet_request_method_name == "getHeader"
                        unless endpoint_parameters.any? { |param| param.name == parameter_name }
                          endpoint_parameters << Param.new(parameter_name, "", "header")
                        end
                        i += 6
                        next
                      end
                    end
                  end
                end
              end

              i += 1
            end
          else
            # Map fields of user-defined class to parameters.
            if package_class_map.has_key?(parameter_type)
              package_class = package_class_map[parameter_type]
              package_class.fields.values.each do |field|
                if field.access_modifier == "public" || field.has_setter?
                  param_default_value = default_value.nil? ? field.init_value : default_value
                  endpoint_parameters << Param.new(field.name, param_default_value, parameter_format)
                end
              end
            end
          end
        end
      end

      endpoint_parameters
    end
  end
end
