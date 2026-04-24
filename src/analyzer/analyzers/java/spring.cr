require "../../../models/analyzer"
require "../../../minilexers/java"
require "../../../miniparsers/java"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../miniparsers/java_parameter_extractor_ts"
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

            # Extract URL mappings + parameters from Spring MVC annotated classes.
            #
            # Fully tree-sitter-based: `TreeSitterJavaRouteExtractor`
            # handles routing (verb, path, class prefix, `@FeignClient`,
            # path/method arrays) and `TreeSitterJavaParameterExtractor`
            # handles parameter extraction (@RequestParam / @RequestBody
            # / @RequestHeader / @PathVariable, primitives, DTO field
            # expansion, HttpServletRequest body scanning, `consumes = ...`).
            #
            # `JavaParser` is still invoked above (for import /
            # same-package resolution) so that DTO classes imported
            # from sibling files stay discoverable. The resulting
            # `class_map` is rebuilt here as a TS-shaped FieldInfo
            # index.
            class_map = package_class_map.merge(import_map)

            # Build a TS-shaped DTO index from the JavaParser class_map
            # plus an in-file TS sweep so same-file DTOs (the common
            # case in fixtures) are picked up even when JavaParser's
            # import/package resolution missed them.
            dto_index = Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)).new
            Noir::TreeSitterJavaParameterExtractor.extract_class_fields(content).each do |k, v|
              dto_index[k] = v
            end
            class_map.each do |class_name, class_model|
              next if dto_index.has_key?(class_name)
              dto_index[class_name] = class_model.fields.values.map do |field|
                Noir::TreeSitterJavaParameterExtractor::FieldInfo.new(
                  field.name,
                  field.access_modifier,
                  field.has_setter?,
                  field.init_value,
                )
              end
            end

            feign_clients = Noir::TreeSitterJavaParameterExtractor.extract_feign_client_classes(content)

            Noir::TreeSitterJavaRouteExtractor.extract_routes(content).each do |route|
              is_feign_client = feign_clients.includes?(route.class_name)

              parameter_format = Noir::TreeSitterJavaParameterExtractor.extract_consumes(
                content, route.class_name, route.method_name
              )
              if parameter_format.nil? && route.verb == "POST"
                parameter_format = "form"
              end

              parameters = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
                content, route.class_name, route.method_name, route.verb, parameter_format, dto_index
              )

              # webflux base-path normalisation — drop the trailing `/`
              # when the route path already starts with one so the join
              # doesn't produce `//`.
              base_path = webflux_base_path
              if base_path.ends_with?("/") && route.path.starts_with?("/")
                base_path = base_path[..-2]
              end

              line = route.line + 1
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
  end
end
