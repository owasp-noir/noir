require "../../../models/analyzer"
require "../../../minilexers/kotlin"
require "../../../miniparsers/kotlin"
require "../../../utils/utils.cr"

module Analyzer::Kotlin
  class Spring < Analyzer
    REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
    REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/
    FILE_CONTENT_CACHE      = Hash(String, String).new
    KOTLIN_EXTENSION        = "kt"
    HTTP_METHODS            = %w[GET POST PUT DELETE PATCH]

    def analyze
      parser_map = Hash(String, KotlinParser).new
      package_map = Hash(String, Hash(String, KotlinParser::ClassModel)).new
      webflux_base_path_map = Hash(String, String).new

      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)

        if File.directory?(path)
          process_directory(path, webflux_base_path_map)
        elsif path.ends_with?(".#{KOTLIN_EXTENSION}")
          process_kotlin_file(path, parser_map, package_map, webflux_base_path_map)
        end
      end

      Fiber.yield
      @result
    end

    # Process directory to extract WebFlux base path from 'application.yml'
    private def process_directory(path : String, webflux_base_path_map : Hash(String, String))
      if path.ends_with?("/src")
        application_yml_path = File.join(path, "main/resources/application.yml")
        if File.exists?(application_yml_path)
          begin
            config = YAML.parse(File.read(application_yml_path))
            spring = config["spring"]
            if spring
              webflux = spring["webflux"]
              if webflux
                base_path = webflux["base-path"]
                if base_path
                  webflux_base_path = base_path.as_s
                  webflux_base_path_map[path] = webflux_base_path if webflux_base_path
                end
              end
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
    end

    # Process individual Kotlin files to analyze Spring WebFlux annotations
    private def process_kotlin_file(path : String, parser_map : Hash(String, KotlinParser), package_map : Hash(String, Hash(String, KotlinParser::ClassModel)), webflux_base_path_map : Hash(String, String))
      content = fetch_file_content(path)
      parser = parser_map[path]? || create_parser(Path.new(path), content)
      parser_map[path] ||= parser
      tokens = parser.tokens

      package_name = parser.get_package_name(tokens)
      return if package_name.empty?

      root_source_directory = parser.get_root_source_directory(path, package_name)
      package_directory = Path.new(path).parent

      import_map = process_imports(parser, root_source_directory, package_directory, path, parser_map)
      package_class_map = package_map[package_directory.to_s]? || process_package_classes(package_directory, path, parser_map)
      package_map[package_directory.to_s] ||= package_class_map

      class_map = package_class_map.merge(import_map)
      parser.classes.each { |source_class| class_map[source_class.name] = source_class }

      match = webflux_base_path_map.find { |base_path, _| path.starts_with?(base_path) }
      webflux_base_path = match ? match.last : ""
      process_class_annotations(path, parser, class_map, webflux_base_path)
    end

    # Fetch content of a file and cache it
    private def fetch_file_content(path : String) : String
      FILE_CONTENT_CACHE[path] ||= File.read(path, encoding: "utf-8", invalid: :skip)
    end

    # Create a Kotlin parser for a given path and content
    private def create_parser(path : Path, content : String = "") : KotlinParser
      content = fetch_file_content(path.to_s) if content.empty?
      lexer = KotlinLexer.new
      tokens = lexer.tokenize(content)
      KotlinParser.new(path.to_s, tokens)
    end

    # Process imports in the Kotlin file to gather class models
    private def process_imports(parser : KotlinParser, root_source_directory : Path, package_directory : Path, current_path : String, parser_map : Hash(String, KotlinParser)) : Hash(String, KotlinParser::ClassModel)
      import_map = Hash(String, KotlinParser::ClassModel).new
      parser.import_statements.each do |import_statement|
        import_path = import_statement.gsub(".", "/")
        if import_path.ends_with?("/*")
          process_wildcard_import(root_source_directory, import_path, current_path, parser_map, import_map)
        else
          process_single_import(root_source_directory, import_path, package_directory, parser_map, import_map)
        end
      end

      import_map
    end

    # Handle wildcard imports
    private def process_wildcard_import(root_source_directory : Path, import_path : String, current_path : String, parser_map : Hash(String, KotlinParser), import_map : Hash(String, KotlinParser::ClassModel))
      import_directory = root_source_directory.join(import_path[0..-3])
      return unless Dir.exists?(import_directory)

      # TODO: Be aware that the import file location might differ from the actual file system path.
      Dir.glob("#{escape_glob_path(import_directory.to_s)}/*.#{KOTLIN_EXTENSION}") do |path|
        next if path == current_path
        parser = parser_map[path]? || create_parser(Path.new(path))
        parser_map[path] ||= parser
        parser.classes.each { |package_class| import_map[package_class.name] = package_class }
      end
    end

    # Handle single imports
    private def process_single_import(root_source_directory : Path, import_path : String, package_directory : Path, parser_map : Hash(String, KotlinParser), import_map : Hash(String, KotlinParser::ClassModel))
      source_path = root_source_directory.join("#{import_path}.#{KOTLIN_EXTENSION}")
      return if source_path.dirname == package_directory || !File.exists?(source_path)
      # TODO: Be aware that the import file location might differ from the actual file system path.
      parser = parser_map[source_path.to_s]? || create_parser(source_path)
      parser_map[source_path.to_s] ||= parser
      parser.classes.each { |package_class| import_map[package_class.name] = package_class }
    end

    # Process all classes in the same package directory
    private def process_package_classes(package_directory : Path, current_path : String, parser_map : Hash(String, KotlinParser)) : Hash(String, KotlinParser::ClassModel)
      package_class_map = Hash(String, KotlinParser::ClassModel).new
      Dir.glob("#{escape_glob_path(package_directory.to_s)}/*.#{KOTLIN_EXTENSION}") do |path|
        next if path == current_path
        parser = parser_map[path]? || create_parser(Path.new(path))
        parser_map[path] ||= parser
        parser.classes.each { |package_class| package_class_map[package_class.name] = package_class }
      end
      package_class_map
    end

    # Process class annotations to find URL mappings and HTTP methods
    private def process_class_annotations(path : String, parser : KotlinParser, class_map : Hash(String, KotlinParser::ClassModel), webflux_base_path : String)
      parser.classes.each do |class_model|
        class_annotation = class_model.annotations["@RequestMapping"]?

        url = class_annotation ? extract_url_from_annotation(class_annotation) : ""
        class_model.methods.values.each do |method|
          process_method_annotations(path, parser, method, class_map, webflux_base_path, url)
        end
      end
    end

    # Extract URL from class annotation
    private def extract_url_from_annotation(annotation_model : KotlinParser::AnnotationModel) : String
      return "" if annotation_model.params.empty?
      url_token = annotation_model.params[0][-1]
      url = url_token.type == :STRING_LITERAL ? url_token.value[1..-2] : ""
      url.ends_with?("*") ? url[0..-2] : url
    end

    # Process method annotations to find specific mappings and create endpoints
    private def process_method_annotations(path : String, parser : KotlinParser, method : KotlinParser::MethodModel, class_map : Hash(String, KotlinParser::ClassModel), webflux_base_path : String, url : String)
      method.annotations.values.each do |method_annotation|
        next unless method_annotation.name.ends_with?("Mapping")

        request_optional, parameter_format = extract_request_methods_and_format(parser, method_annotation)
        url_paths = method_annotation.name.starts_with?("@") ? extract_mapping_paths(parser, method_annotation) : [""]
        details = Details.new(PathInfo.new(path, method_annotation.tokens[0].line))
        url_paths += request_optional["values"]
        url_paths += request_optional["paths"]

        create_endpoints(webflux_base_path, url, url_paths, request_optional, parser, method, parameter_format, class_map, details)
      end
    end

    # Extract HTTP methods and parameter format from annotation
    private def extract_request_methods_and_format(parser : KotlinParser, annotation_model : KotlinParser::AnnotationModel) : Tuple(Hash(String, Array(String)), String?)
      parameter_format = nil
      request_optional = Hash(String, Array(String)).new
      request_optional["methods"] = Array(String).new
      request_optional["params"] = Array(String).new
      request_optional["headers"] = Array(String).new
      request_optional["values"] = Array(String).new
      request_optional["paths"] = Array(String).new

      annotation_model.params.each do |tokens|
        next if tokens.size < 3
        next if tokens[2].value != "[" && tokens[2].value != "arrayOf"
        bracket_index = tokens[2].value != "arrayOf" ? tokens[2].index : tokens[2].index + 1

        case tokens[0].value
        when "method"
          parser.parse_formal_parameters(bracket_index).each do |param_tokens|
            method_index = param_tokens[0].value != "RequestMethod" ? 0 : 2
            request_optional["methods"] << param_tokens[method_index].value
          end
        when "consumes"
          parser.parse_formal_parameters(bracket_index).each do |param_tokens|
            if param_tokens.size > 0 && param_tokens[0].type == :STRING_LITERAL
              if param_tokens.size > 0 && param_tokens[0].type == :STRING_LITERAL
                parameter_format = case param_tokens[0].value[1..-2].upcase
                                   when "APPLICATION/X-WWW-FORM-URLENCODED"
                                     "form"
                                   when "APPLICATION/JSON"
                                     "json"
                                   end
                break
              end
            end
          end
        when "params"
          parser.parse_formal_parameters(bracket_index).each do |param_tokens|
            if param_tokens.size > 0 && param_tokens[0].type == :STRING_LITERAL
              request_optional["params"] << param_tokens[0].value[1..-2]
            end
          end
        when "headers"
          parser.parse_formal_parameters(bracket_index).each do |param_tokens|
            if param_tokens.size > 0 && param_tokens[0].type == :STRING_LITERAL
              request_optional["headers"] << param_tokens[0].value[1..-2]
            end
          end
        when "value"
          parser.parse_formal_parameters(bracket_index).each do |param_tokens|
            if param_tokens.size > 0 && param_tokens[0].type == :STRING_LITERAL
              request_optional["values"] << param_tokens[0].value[1..-2]
            end
          end
        when "path"
          parser.parse_formal_parameters(bracket_index).each do |param_tokens|
            if param_tokens.size > 0 && param_tokens[0].type == :STRING_LITERAL
              request_optional["paths"] << param_tokens[0].value[1..-2]
            end
          end
        end
      end

      if request_optional["methods"].empty?
        if annotation_model.name == "@RequestMapping"
          # Default to all HTTP methods if no method is specified
          request_optional["methods"].concat(HTTP_METHODS)
        else
          # Extract HTTP method from annotation name
          http_method = HTTP_METHODS.find { |method| annotation_model.name.upcase == "@#{method}MAPPING" }
          request_optional["methods"].push(http_method) if http_method
        end
      end

      {request_optional, parameter_format}
    end

    # Extract URL mapping paths from annotation parameters
    private def extract_mapping_paths(parser : KotlinParser, annotation_model : KotlinParser::AnnotationModel) : Array(String)
      return [""] if annotation_model.params.empty?
      get_mapping_path(parser, annotation_model.params)
    end

    # Create endpoints for the extracted HTTP methods and paths
    private def create_endpoints(webflux_base_path : String, url : String, url_paths : Array(String), request_optional : Hash(String, Array(String)), parser : KotlinParser, method : KotlinParser::MethodModel, parameter_format : String?, class_map : Hash(String, KotlinParser::ClassModel), details : Details)
      # Iterate over each URL path to create full URLs
      url_paths.each do |url_path|
        full_url = join_path(webflux_base_path, url, url_path)

        # Iterate over each request method to create endpoints
        request_optional["methods"].each do |request_method|
          # Determine parameter format if not specified
          parameter_format ||= determine_parameter_format(request_method)

          # Get parameters for the endpoint
          parameters = get_endpoint_parameters(parser, method, parameter_format, class_map)

          # Add query or form parameters
          add_params(parameters, request_optional["params"], parameter_format)

          # Add header parameters
          add_params(parameters, request_optional["headers"], "header")

          # Create and store the endpoint
          @result << Endpoint.new(full_url, request_method, parameters, details)
        end
      end
    end

    # Determine the parameter format based on the request method
    private def determine_parameter_format(request_method)
      case request_method
      when "POST", "PUT", "DELETE", "PATCH"
        "form"
      when "GET"
        "query"
      end
    end

    # Add parameters to the parameters array
    # params: Array of parameter strings
    # default_format: Default format for the parameters (query, form, header)
    private def add_params(parameters, params, default_format)
      params.each do |param|
        format = default_format || "query"
        param, default_value = param.includes?("=") ? param.split("=") : [param, ""]
        new_param_obj = Param.new(param, default_value, format)

        # Add parameter if it doesn't already exist in the parameters array
        parameters << new_param_obj unless parameters.includes?(new_param_obj)
      end
    end

    # Extract mapping paths from annotation parameters
    private def get_mapping_path(parser : KotlinParser, method_params : Array(Array(Token))) : Array(String)
      url_paths = Array(String).new
      path_argument_index = method_params.index { |param| param[0].value == "value" } || 0
      path_parameter_tokens = method_params[path_argument_index]
      if path_parameter_tokens[-1].type == :STRING_LITERAL
        url_paths << path_parameter_tokens[-1].value[1..-2]
      elsif path_parameter_tokens[-1].type == :RBRACE
        i = path_parameter_tokens.size - 2
        while i > 0
          parameter_token = path_parameter_tokens[i]
          case parameter_token.type
          when :LCURL
            break
          when :COMMA
            i -= 1
            next
          when :STRING_LITERAL
            url_paths << parameter_token.value[1..-2]
          else
            break
          end
          i -= 1
        end
      end

      url_paths
    end

    # Get endpoint parameters from the method's annotation and signature
    private def get_endpoint_parameters(parser : KotlinParser, method : KotlinParser::MethodModel, parameter_format : String?, package_class_map : Hash(String, KotlinParser::ClassModel)) : Array(Param)
      endpoint_parameters = Array(Param).new
      method.params.each do |tokens|
        next if tokens.size < 3

        i = 0
        while i < tokens.size
          case tokens[i + 1].type
          when :ANNOTATION
            i += 1
          when :LPAREN
            rparen = parser.find_bracket_partner(tokens[i + 1].index)
            if rparen && tokens[i + (rparen - tokens[i + 1].index) + 2].type == :ANNOTATION
              i += rparen - tokens[i + 1].index + 2
            else
              break
            end
          else
            break
          end
        end

        token = tokens[i]
        parameter_index = tokens[-1].value != "?" ? -1 : -2
        if tokens[parameter_index].value == "Pageable"
          next if parameter_format.nil?
          endpoint_parameters << Param.new("page", "", parameter_format)
          endpoint_parameters << Param.new("size", "", parameter_format)
          endpoint_parameters << Param.new("sort", "", parameter_format)
        else
          name = token.value
          parameter_format = get_parameter_format(name, parameter_format)
          next if parameter_format.nil?

          default_value, parameter_name, parameter_type = extract_parameter_details(tokens, parser, i)
          next if parameter_name.empty? || parameter_type.nil?

          param_default_value = default_value.nil? ? "" : default_value
          if parameter_type.downcase.in?(%w[long int integer char boolean string multipartfile])
            endpoint_parameters << Param.new(parameter_name, param_default_value, parameter_format)
          else
            add_user_defined_class_params(package_class_map, parameter_type, default_value, parameter_name, parameter_format, endpoint_parameters)
          end
        end
      end
      endpoint_parameters
    end

    # Get parameter format based on annotation name
    private def get_parameter_format(name : String, current_format : String?) : String?
      case name
      when "@RequestBody"
        current_format || "json"
      when "@RequestParam"
        "query"
      when "@RequestHeader"
        "header"
      when "@CookieValue"
        "cookie"
      when "@PathVariable"
        nil
      when "@ModelAttribute"
        current_format || "form"
      else
        current_format || "query"
      end
    end

    # Extract details of parameters from tokens
    private def extract_parameter_details(tokens : Array(Token), parser : KotlinParser, index : Int32) : Tuple(String, String, String?)
      default_value = ""
      parameter_name = ""
      parameter_type = nil

      if tokens[index + 1].type == :LPAREN
        attributes = parser.parse_formal_parameters(tokens[index + 1].index)
        attributes.each do |attribute_tokens|
          if attribute_tokens.size > 2
            attribute_name = attribute_tokens[0].value
            attribute_value = attribute_tokens[2].value
            case attribute_name
            when "value", "name"
              parameter_name = attribute_value
            when "defaultValue"
              default_value = attribute_value
            end
          else
            parameter_name = attribute_tokens[0].value
          end
        end
      end

      colon_index = tokens[-1].value == "?" ? -3 : -2
      if tokens[colon_index].type == :COLON
        parameter_name = tokens[-3].value if parameter_name.empty? && tokens[-3].type == :IDENTIFIER
        parameter_type = tokens[-1].type == :QUEST ? tokens[-2].value : tokens[-1].value if tokens[-1].type == :IDENTIFIER
      elsif tokens[colon_index + 1].type == :RANGLE
        parameter_type = tokens[-2].value
        parameter_name = tokens[-6].value if tokens[-5].type == :COLON
      end

      default_value = default_value[1..-2] if default_value.size > 1 && default_value[0] == '"' && default_value[-1] == '"'
      parameter_name = parameter_name[1..-2] if parameter_name.size > 1 && parameter_name[0] == '"' && parameter_name[-1] == '"'

      {default_value, parameter_name, parameter_type}
    end

    # Add parameters from user-defined class fields
    private def add_user_defined_class_params(package_class_map : Hash(String, KotlinParser::ClassModel), parameter_type : String, default_value : String?, parameter_name : String, parameter_format : String?, endpoint_parameters : Array(Param))
      if package_class_map.has_key?(parameter_type)
        package_class = package_class_map[parameter_type]
        if package_class.enum_class?
          param_default_value = default_value.nil? ? "" : default_value
          endpoint_parameters << Param.new(parameter_name, param_default_value, parameter_format)
        else
          package_class.fields.values.each do |field|
            if package_class_map.has_key?(field.type) && parameter_type != field.type
              add_user_defined_class_params(package_class_map, field.type, field.init_value, field.name, parameter_format, endpoint_parameters)
            else
              if field.access_modifier == "public" || field.has_setter?
                param_default_value = default_value.nil? ? field.init_value : default_value
                endpoint_parameters << Param.new(field.name, param_default_value, parameter_format)
              end
            end
          end
        end
      end
    end
  end
end
