require "../../models/analyzer"
require "../../minilexers/java"
require "../../miniparsers/java"

class AnalyzerSpring < Analyzer
  REGEX_CLASS_DEFINITION  = /^(((public|private|protected|default)\s+)|^)class\s+/
  REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
  REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/

  def analyze
    # Source Analysis
    begin
      Dir.glob("#{@base_path}/**/*") do |path|
        next if File.directory?(path)

        url = ""
        if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
          content = File.read(path, encoding: "utf-8", invalid: :skip)

          lexer = JavaLexer.new
          tokens = lexer.tokenize(content)
          parser = JavaParser.new
          parser.parse(tokens)
          has_spring_web_bind_class_been_import = false
          parser.@import_statements.each do |import_statement|
            if import_statement.includes? "org.springframework.web.bind.annotation."
              has_spring_web_bind_class_been_import = true
            end
          end
          if has_spring_web_bind_class_been_import            
            # Spring Web
            parser.@classes_tokens.each do |class_tokens|
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
              
              parser.parse_methods(class_tokens).each do |method_tokens|                
                method_annotations = parser.parse_annotations(tokens, method_tokens[0].index)
                method_annotations.each do |method_annotation_tokens|
                  if method_annotation_tokens[1].value == "RequestMapping"
                    annotation_parameters = parser.parse_formal_parameters(tokens, method_annotation_tokens[1].index)

                    url_path = ""
                    line = method_annotation_tokens[1].line
                    if annotation_parameters.size != 0            
                      url_path = annotation_parameters[0][-1].value[1..-2]
                      if url.ends_with?("/") && url_path.starts_with?("/")
                        url_path = url_path[1..-1]
                      end
                      line = annotation_parameters[0][-1].line
                    end
                    parameters = get_endpoint_parameters(parser, tokens, method_tokens[0].index)
                    details = Details.new(PathInfo.new(path, line))

                    method_flag = false
                    if annotation_parameters.size > 1
                      annotation_parameters.each do |annotation_parameter_tokens|
                        if annotation_parameter_tokens[0].value == "method"
                          method = annotation_parameter_tokens[-1].value
                          method_flag = true
                          @result << Endpoint.new("#{url}#{url_path}", method, parameters, details)
                          break
                        end
                      end
                    end

                    unless method_flag
                      ["GET", "POST", "PUT", "DELETE", "PATCH"].each do |method|
                        @result << Endpoint.new("#{url}#{url_path}", method, details)
                      end
                    end
                  else
                    ["GetMapping", "PostMapping", "PutMapping", "DeleteMapping", "PatchMapping"].each do |method_mapping|
                      if method_annotation_tokens[1].value == method_mapping
                        url_path = ""
                        line = method_annotation_tokens[1].line
                        method = method_mapping[0..-8].upcase
                        parameters = get_endpoint_parameters(parser, tokens, method_tokens[0].index)
                        
                        if tokens[method_annotation_tokens[1].index + 1].type == :LPAREN
                          annotation_parameters = parser.parse_formal_parameters(tokens, method_annotation_tokens[1].index)
                          method_path_token = annotation_parameters[0][-1]
                          if method_path_token.type == :STRING_LITERAL                            
                            url_path = method_path_token.value[1..-2]
                            if url.ends_with?("/") && url_path.starts_with?("/")
                              url_path = url_path[1..-1]
                            end
                          else
                            # error case
                            next
                          end
                        end

                        details = Details.new(PathInfo.new(path, line))
                        @result << Endpoint.new("#{url}#{url_path}", method, parameters, details)
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
    rescue e      
      logger.debug e
    end
    Fiber.yield

    @result
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
