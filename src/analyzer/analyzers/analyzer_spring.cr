require "../../models/analyzer"
require "../../minilexers/java"
require "../../miniparsers/java"

class AnalyzerSpring < Analyzer
  REGEX_CLASS_DEFINITION  = /^(((public|private|protected|default)\s+)|^)class\s+/
  REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
  REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/

  def analyze
    # Source Analysis
    Dir.glob("#{@base_path}/**/*") do |path|
      next if File.directory?(path)

      url = ""
      if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
        content = File.read(path, encoding: "utf-8", invalid: :skip)

        lexer = JavaLexer.new
        tokens = lexer.tokenize(content)
        parser = JavaParser.new
        parser.parse(tokens)
        has_spring_web_bind_package_been_import = false
        parser.@import_statements.each do |import_statement|
          if import_statement.includes? "org.springframework.web.bind.annotation."
            has_spring_web_bind_package_been_import = true
          end
        end

        # Spring MVC Router (Controller)
        if has_spring_web_bind_package_been_import
          parser.@classes_tokens.each do |class_tokens|
            # Parse the base url of the class
            class_annotations = parser.parse_annotations(tokens, class_tokens[0].index)
            class_annotations.each do |class_annotation|
              if class_annotation[1].value == "RequestMapping"
                class_path_token = parser.parse_formal_parameters(tokens, class_annotation[1].index)[0][-1]
                if class_path_token.type == :STRING_LITERAL
                  url = class_path_token.value[1..-2]
                  if url.ends_with? "*"
                    url = url[0..-2]
                  end
                end
              end
            end
            
            # Parse the methods of the class
            parser.parse_methods(class_tokens).each do |method_tokens|                
              # Parse the method annotations
              method_annotations = parser.parse_annotations(tokens, method_tokens[0].index)
              method_annotations.each do |method_annotation_tokens|
                url_paths = Array(String).new
                annotation_name_token = method_annotation_tokens[1]
                # If the method is annotated with @RequestMapping
                if annotation_name_token.value == "RequestMapping"
                  if tokens[annotation_name_token.index + 1].type == :LPAREN
                    url_paths = get_mapping_path(parser, tokens, method_annotation_tokens[1].index)
                  else
                    url_paths = [""]
                  end                                    

                  line = annotation_name_token.line
                  parameters = get_endpoint_parameters(parser, tokens, method_tokens[0].index)
                  details = Details.new(PathInfo.new(path, line))

                  # Parse the method parameter (method = "GET" or "POST" or "PUT" or "DELETE" or "PATCH")
                  method_flag = false
                  annotation_parameters = parser.parse_formal_parameters(tokens, annotation_name_token.index)
                  annotation_parameters.each do |annotation_parameter_tokens|
                    if annotation_parameter_tokens.size > 2
                      if annotation_parameter_tokens[0].value == "method"
                        method = annotation_parameter_tokens[-1].value
                        method_flag = true
                        url_paths.each do |url_path|
                          @result << Endpoint.new("#{url}#{url_path}", method, parameters, details)                          
                        end
                        break
                      end
                    end
                  end

                  # If the method is not annotated with @RequestMapping, then 5 methods are allowed
                  unless method_flag
                    ["GET", "POST", "PUT", "DELETE", "PATCH"].each do |method|
                      url_paths.each do |url_path|
                        @result << Endpoint.new("#{url}#{url_path}", method, parameters, details)
                      end
                    end
                  end
                else
                  # If the method is annotated with @GetMapping, @PostMapping, @PutMapping, @DeleteMapping, @PatchMapping
                  ["GetMapping", "PostMapping", "PutMapping", "DeleteMapping", "PatchMapping"].each do |method_mapping|
                    if annotation_name_token.value == method_mapping
                      line = annotation_name_token.line
                      method = method_mapping[0..-8].upcase
                      parameters = get_endpoint_parameters(parser, tokens, method_tokens[0].index)
                      
                      # Parse the path paremeter
                      if tokens[annotation_name_token.index + 1].type == :LPAREN
                        url_paths = get_mapping_path(parser, tokens, annotation_name_token.index)
                      else
                        # If the path parameter is not specified, then the path is ""
                        url_paths = [""]
                      end

                      details = Details.new(PathInfo.new(path, line))
                      url_paths.each do |url_path|
                        @result << Endpoint.new("#{url}#{url_path}", method, parameters, details)
                      end
                    end
                  end
                end
              end
            end
          end
        else
          # Reactive Router
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

  def get_mapping_path(parser : JavaParser, tokens : Array(Token), mapping_token_index : Int32)
    # 1. Search for the value of the @xxxxxMapping annotation
    # 2. If the value is a string literal, return it
    # 3. If the value is an array, return each element
    # 4. Other case return empty array
    url_paths = Array(String).new
    mapping_parameters = parser.parse_formal_parameters(tokens, mapping_token_index)
    if mapping_parameters[0].size != 0
      path_argument_index = 0
      mapping_parameters.each_with_index do |mapping_parameter, index|
        if mapping_parameter[0].type == :IDENTIFIER && mapping_parameter[0].value == "value"
          path_argument_index = index
        end
      end

      path_parameter_tokens = mapping_parameters[path_argument_index]
      if path_parameter_tokens[-1].type == :STRING_LITERAL
        # @GetMapping("/abc") or @GetMapping(value = "/abc")
        url_paths << path_parameter_tokens[-1].value[1..-2]
      elsif path_parameter_tokens[-1].type == :RBRACE
        # @GetMapping({"/abc", "/def"}) or @GetMapping(value = {"/abc", "/def"})
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
            puts parameter_token.to_s
            break
          end

          i -= 1
        end      
      end      
    end

    url_paths
  end

  def get_endpoint_parameters(parser : JavaParser, tokens : Array(Token), method_token_index : Int32) : Array(Param)
    endpoint_parameters = Array(Param).new                   
    parser.parse_formal_parameters(tokens, method_token_index).each do |formal_parameter_tokens|
      next if formal_parameter_tokens.size == 0

      parameter_type = nil
      if formal_parameter_tokens[-1].type == :IDENTIFIER
        if formal_parameter_tokens[0].type == :AT
          if formal_parameter_tokens[1].value == "PathVariable"
            next
          elsif formal_parameter_tokens[1].value == "RequestBody"
            parameter_type = "form"
          elsif formal_parameter_tokens[1].value == "RequestParam"
            parameter_type = "query"
          else
            next # unknown parameter type
          end
        end
        
        if !parameter_type.nil?
          parameter_name = formal_parameter_tokens[-1].value # case of "@RequestParam String a"
          if formal_parameter_tokens[-1].type != IDENTIFIER
            if formal_parameter_tokens[2].type == :LPAREN && formal_parameter_tokens[3].type == :STRING_LITERAL
              parameter_name_token = formal_parameter_tokens[3] # case of "@RequestParam("a") String a"
              parameter_name = parameter_name_token.value[1..-2]                               
            end
          end

          endpoint_parameters << Param.new(parameter_name, "", parameter_type)                              
        end
      end                          
    end

    endpoint_parameters
  end
end

def analyzer_spring(options : Hash(Symbol, String))
  instance = AnalyzerSpring.new(options)
  instance.analyze
end
