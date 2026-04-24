require "../../../models/analyzer"
require "../../../minilexers/java"
require "../../../miniparsers/java"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../utils/parser_limit"

module Analyzer::Java
  class Spring < Analyzer
    REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
    REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/
    FILE_CONTENT_CACHE      = Hash(String, String).new

    def analyze
      parser_map = Hash(String, JavaParser).new
      package_map = Hash(String, Hash(String, ClassModel)).new
      webflux_base_path_map = Hash(String, String).new
      depth = 0

      file_list = all_files()
      file_list.each do |path|
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
              rescue
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
              rescue
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
          feign_client_package = "org.springframework.cloud.openfeign.FeignClient"
          has_spring_bindings = content.includes?(spring_web_bind_package)
          has_feign_bindings = content.includes?(feign_client_package) || content.includes?("@FeignClient")

          if has_spring_bindings || has_feign_bindings
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

            import_map = process_imports(parser, root_source_directory, package_directory, path, parser_map, depth)

            package_class_map = package_map[package_directory]?
            if package_class_map.nil?
              package_class_map = process_package_classes(parser, package_directory, path, parser_map, depth)
              package_map[package_directory] = package_class_map
            end

            # Extract URL mappings from Spring MVC annotated classes.
            #
            # Hybrid approach: tree-sitter (`TreeSitterJavaRouteExtractor`)
            # handles the pure routing layer — verb, path, class prefix
            # composition, `@FeignClient` interfaces, method/path arrays
            # in `@RequestMapping`. The legacy `JavaParser` is still used
            # for *parameter extraction* (DTO field introspection,
            # `@RequestParam` / `@RequestBody` / `HttpServletRequest`
            # body scanning) because that logic is deeply tied to
            # `MethodModel` and moving it is a separate porting step.
            class_map = package_class_map.merge(import_map)

            class_models_by_name = Hash(String, ClassModel).new
            parser.classes.each { |cm| class_models_by_name[cm.name] = cm }

            Noir::TreeSitterJavaRouteExtractor.extract_routes(content).each do |route|
              class_model = class_models_by_name[route.class_name]?
              next if class_model.nil?

              is_feign_client = !class_model.annotations["FeignClient"]?.nil?
              method_model = class_model.methods[route.method_name]?
              next if method_model.nil?

              # Pick the @*Mapping annotation on this method so we can
              # still read `consumes = ...` for parameter_format. Method
              # name collisions across overloads collapse onto the same
              # MethodModel (pre-existing limitation), which matches
              # legacy behaviour.
              mapping_annotation = method_model.annotations.values.find do |a|
                a.name.ends_with?("Mapping")
              end
              parameter_format = consumes_parameter_format(mapping_annotation)
              if parameter_format.nil? && route.verb == "POST"
                parameter_format = "form"
              end

              parameters = get_endpoint_parameters(
                parser, route.verb, method_model, parameter_format, class_map
              )

              # webflux base-path normalisation — drop the trailing `/`
              # when the route path already starts with one so the join
              # doesn't produce `//`.
              base_path = webflux_base_path
              if base_path.ends_with?("/") && route.path.starts_with?("/")
                base_path = base_path[..-2]
              end

              # Prefer the MethodModel's annotation line (1-based,
              # matches legacy) when available. Fall back to the
              # tree-sitter row (0-based) + 1.
              line = mapping_annotation ? mapping_annotation.tokens[0].line : route.line + 1
              details = Details.new(PathInfo.new(path, line))

              endpoint = Endpoint.new(
                join_paths(base_path, route.path), route.verb, parameters, details, is_feign_client
              )
              @result << endpoint
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
                @result << Endpoint.new(join_paths(url, endpoint), method, details)
              end
            end
          end
        end
      end
      Fiber.yield

      @result
    end

    private def process_imports(parser : JavaParser, root_source_directory : Path, package_directory : String, current_path : String, parser_map : Hash(String, JavaParser), depth : Int32) : Hash(String, ClassModel)
      import_map = Hash(String, ClassModel).new
      parser.import_statements.each do |import_statement|
        import_path = import_statement.gsub(".", "/")
        if import_path.ends_with?("/*")
          import_directory = root_source_directory.join(import_path[..-3])
          if Dir.exists?(import_directory)
            Dir.glob("#{escape_glob_path(import_directory.to_s)}/*.java") do |_path|
              next if current_path == _path
              if !parser_map.has_key?(_path)
                next unless ParserLimit.allow_depth?(depth)
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
            next unless ParserLimit.allow_depth?(depth)
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

      import_map
    end

    private def process_package_classes(parser : JavaParser, package_directory : String, current_path : String, parser_map : Hash(String, JavaParser), depth : Int32) : Hash(String, ClassModel)
      package_class_map = Hash(String, ClassModel).new
      Dir.glob("#{escape_glob_path(package_directory)}/*.java") do |_path|
        next if current_path == _path
        if !parser_map.has_key?(_path)
          next unless ParserLimit.allow_depth?(depth)
          _parser = create_parser(Path.new(_path))
          parser_map[_path] = _parser
        else
          _parser = parser_map[_path]
        end

        _parser.classes.each do |package_class|
          package_class_map[package_class.name] = package_class
        end
      end

      parser.classes.each do |package_class|
        package_class_map[package_class.name] = package_class
      end

      package_class_map
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

    # Return "form" / "json" when the `@*Mapping` annotation declares
    # a `consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE` or
    # `APPLICATION_JSON_VALUE`. nil otherwise (callers supply their
    # own default — POST, for example, falls back to "form").
    private def consumes_parameter_format(mapping_annotation) : String?
      return if mapping_annotation.nil?
      mapping_annotation.params.each do |param_tokens|
        next unless param_tokens.size > 2
        next unless param_tokens[0].value == "consumes"
        value = param_tokens[-1].value
        return "form" if value.ends_with?("APPLICATION_FORM_URLENCODED_VALUE")
        return "json" if value.ends_with?("APPLICATION_JSON_VALUE")
      end
      nil
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
          next unless mapping_parameter
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

    def get_endpoint_parameters(parser : JavaParser, request_method : String, method : MethodModel, parameter_format : String?, package_class_map : Hash(String, ClassModel)) : Array(Param)
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
            next
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
                    parameter_name = request_param_value
                  elsif request_param_name == "name"
                    parameter_name = request_param_value
                  elsif request_param_name == "defaultValue"
                    default_value = request_param_value
                  end

                  unless parameter_name.nil?
                    if parameter_name.starts_with?("\"") && parameter_name.ends_with?("\"")
                      parameter_name = parameter_name[1..-2]
                    else
                      idx = 2
                      while idx < request_parameter_tokens.size
                        req_param_token = request_parameter_tokens[-idx]
                        break unless req_param_token.type == :IDENTIFIER || req_param_token.type == :DOT
                        parameter_name = req_param_token.value + parameter_name
                        idx += 1
                      end

                      # https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/http/HttpHeaders.html
                      if parameter_name.starts_with?("HttpHeaders.")
                        header_key = parameter_name["HttpHeaders.".size..-1]
                        parameter_name = header_key.split('_').map(&.capitalize).join('-')
                        special_cases = {
                          "Etag"             => "ETag",
                          "Te"               => "TE",
                          "Www-Authenticate" => "WWW-Authenticate",
                          "X-Frame-Options"  => "X-Frame-Options",
                        }
                        if special_cases.has_key?(parameter_name)
                          parameter_name = special_cases[parameter_name]
                        end
                      end
                    end
                  end

                  unless default_value.nil?
                    if default_value.starts_with?("\"") && default_value.ends_with?("\"")
                      default_value = default_value[1..-2]
                    end
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
