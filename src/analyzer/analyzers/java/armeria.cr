require "../../../models/analyzer"
require "../../../minilexers/java"
require "../../../miniparsers/java"

module Analyzer::Java
  class Armeria < Analyzer
    REGEX_SERVER_CODE_BLOCK = /Server\s*\.builder\(\s*\)\s*\.[^;]*build\(\)\s*\./
    REGEX_SERVICE_CODE      = /\.service(If|Under|)?\([^;]+?\)/
    REGEX_ROUTE_CODE        = /\.route\(\)\s*\.\s*(\w+)\s*\(([^\.]*)\)\./

    # HTTP method annotations supported by Armeria
    HTTP_METHOD_ANNOTATIONS = ["Get", "Post", "Put", "Delete", "Patch", "Head", "Options", "Trace"]

    def analyze
      # Source Analysis
      channel = Channel(String).new

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)

                  if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
                    content = File.read(path, encoding: "utf-8", invalid: :skip)

                    # Check for Armeria annotation imports
                    has_armeria_annotations = content.includes?("com.linecorp.armeria.server.annotation.")

                    if has_armeria_annotations
                      # Parse annotation-based services
                      analyze_annotated_service(path, content)
                    end

                    # Parse Server.builder() style (existing logic)
                    details = Details.new(PathInfo.new(path))
                    content.scan(REGEX_SERVER_CODE_BLOCK) do |server_codeblock_match|
                      server_codeblock = server_codeblock_match[0]

                      server_codeblock.scan(REGEX_SERVICE_CODE) do |service_code_match|
                        next if service_code_match.size != 2
                        endpoint_param_index = 0
                        if service_code_match[1] == "If"
                          endpoint_param_index = 1
                        end

                        service_code = service_code_match[0]
                        parameter_code = service_code.split("(")[1]
                        split_params = parameter_code.split(",")
                        next if split_params.size <= endpoint_param_index
                        endpoint = split_params[endpoint_param_index].strip

                        endpoint = endpoint[1..-2]
                        ep = Endpoint.new("#{endpoint}", "GET", details)
                        extract_path_parameters(endpoint, ep)
                        @result << ep
                      end

                      server_codeblock.scan(REGEX_ROUTE_CODE) do |route_code_match|
                        next if route_code_match.size != 3
                        method = route_code_match[1].upcase
                        if method == "PATH"
                          method = "GET"
                        end

                        next if !["GET", "POST", "DELETE", "PUT", "PATCH", "HEAD", "OPTIONS"].includes?(method)

                        endpoint = route_code_match[2].split(")")[0].strip
                        next if endpoint[0] != endpoint[-1]
                        next if endpoint[0] != '"'

                        endpoint = endpoint[1..-2]
                        ep = Endpoint.new("#{endpoint}", method, details)
                        extract_path_parameters(endpoint, ep)
                        @result << ep
                      end
                    end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
      Fiber.yield

      @result
    end

    # Analyze annotation-based Armeria services
    private def analyze_annotated_service(path : String, content : String)
      lexer = JavaLexer.new
      tokens = lexer.tokenize(content)
      parser = JavaParser.new(path, tokens)

      parser.classes.each do |class_model|
        class_model.methods.values.each do |method|
          method.annotations.values.each do |method_annotation|
            # Check if it's an HTTP method annotation
            http_method_index = HTTP_METHOD_ANNOTATIONS.index(method_annotation.name)
            next if http_method_index.nil?

            http_method = HTTP_METHOD_ANNOTATIONS[http_method_index].upcase
            url_path = extract_url_from_annotation(method_annotation)
            next if url_path.empty?

            line = method_annotation.tokens[0].line
            details = Details.new(PathInfo.new(path, line))
            parameters = get_armeria_parameters(parser, method, url_path)

            endpoint = Endpoint.new(url_path, http_method, parameters, details)
            extract_path_parameters(url_path, endpoint)
            @result << endpoint
          end
        end
      end
    end

    # Extract URL path from annotation like @Get("/path") or @Get(value = "/path")
    private def extract_url_from_annotation(method_annotation : AnnotationModel) : String
      return "" if method_annotation.params.empty?

      method_annotation.params.each do |param_tokens|
        next if param_tokens.empty?

        # Handle @Get("/path") - single string literal
        if param_tokens.size == 1 && param_tokens[0].type == :STRING_LITERAL
          value = strip_quotes(param_tokens[0].value)
          return value unless value.empty?
        end

        # Handle @Get(value = "/path") or named parameters
        param_tokens.each_with_index do |token, _|
          if token.type == :STRING_LITERAL
            value = strip_quotes(token.value)
            return value unless value.empty?
          end
        end
      end

      ""
    end

    # Extract parameters from Armeria annotations (@Param, @Header, @RequestObject)
    private def get_armeria_parameters(parser : JavaParser, method : MethodModel, url_path : String) : Array(Param)
      endpoint_parameters = Array(Param).new
      # Extract path parameter names from URL pattern
      path_param_names = Set(String).new
      url_path.scan(/\{(\w+)\}/) do |match|
        path_param_names << match[1] if match.size > 1
      end

      method.params.each do |method_param_tokens|
        next if method_param_tokens.empty?
        next unless method_param_tokens[-1].type == :IDENTIFIER

        # Check for annotation
        if method_param_tokens[0].type == :AT && method_param_tokens.size > 1
          annotation_name = method_param_tokens[1].value

          case annotation_name
          when "Param"
            param_name = extract_annotation_param_name(parser, method_param_tokens)
            # In Armeria, @Param can be either path or query parameter
            # If the param name matches a path template variable, it's a path param
            # Otherwise, it's a query param
            if path_param_names.includes?(param_name)
              # Path parameters are handled separately by extract_path_parameters
              # So we don't add them here to avoid duplicates
              next
            else
              endpoint_parameters << Param.new(param_name, "", "query")
            end
          when "Header"
            param_name = extract_annotation_param_name(parser, method_param_tokens)
            endpoint_parameters << Param.new(param_name, "", "header")
          when "RequestObject"
            # RequestObject typically represents JSON body - we mark it as json param type
            # The actual variable name becomes the parameter name
            param_name = method_param_tokens[-1].value
            endpoint_parameters << Param.new(param_name, "", "json")
          end
        end
      end

      endpoint_parameters
    end

    # Extract parameter name from annotation like @Param("name") or @Param String name
    private def extract_annotation_param_name(parser : JavaParser, method_param_tokens : Array(Token)) : String
      # Default to variable name (last identifier)
      default_name = method_param_tokens[-1].value

      # Check if there's a parenthesis with parameter name
      if method_param_tokens.size > 2 && method_param_tokens[2].type == :LPAREN
        # Parse annotation parameters
        annotation_params = parser.parse_formal_parameters(method_param_tokens, 2)
        annotation_params.each do |param_tokens|
          next if param_tokens.empty?

          # Handle @Param("name") - single string literal
          if param_tokens.size == 1 && param_tokens[0].type == :STRING_LITERAL
            value = strip_quotes(param_tokens[0].value)
            return value unless value.empty?
          end

          # Handle @Header(value = "name") or @Header(name = "name")
          if param_tokens.size > 2
            param_key = param_tokens[0].value
            param_value = param_tokens[-1]
            if (param_key == "value" || param_key == "name") && param_value.type == :STRING_LITERAL
              value = strip_quotes(param_value.value)
              return value unless value.empty?
            end
          end
        end
      end

      default_name
    end

    # Safely strip surrounding quotes from a string literal
    # Handles edge cases like empty strings or malformed literals
    private def strip_quotes(value : String) : String
      return "" if value.size < 2
      value[1..-2]
    end

    # Extract path parameters from URLs like /users/{userId} or /items/{itemId}/comments
    private def extract_path_parameters(url : String, endpoint : Endpoint)
      url.scan(/\{(\w+)\}/) do |match|
        if match.size > 0
          param_name = match[1]
          # Only add if not already present
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
      end
    end
  end
end
