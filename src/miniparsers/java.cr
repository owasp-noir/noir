require "../minilexers/java"
require "../models/minilexer/token"

class JavaParser
  def initialize
    @import_statements = Array(String).new
    @classes_tokens = Array(Array(Token)).new
    @class_annotation = Array(Token).new    
  end

  def parse(tokens : Array(Token))    
    parse_import_statements(tokens)
    parse_classes(tokens)
  end

  def parse_import_statements(tokens : Array(Token))
    import_statements = [] of String
    import_tokens = tokens.select { |token| token.type == :IMPORT }
    import_tokens.each do |import_token|
      next_token_index = import_token.index + 2
      next_token = tokens[next_token_index]

      if next_token && next_token.type == :IDENTIFIER
        import_statement = next_token.value
        next_token_index += 1
        
        while next_token_index < tokens.size && tokens[next_token_index].type == :DOT
          next_token_index += 1
          identifier_token = tokens[next_token_index]
          break if !identifier_token || identifier_token.type != :IDENTIFIER

          import_statement += ".#{identifier_token.value}"
          next_token_index += 1
        end

        @import_statements << import_statement
      end
    end
  end

  def parse_formal_parameters(tokens : Array(Token), cursor : Int32)
    lparen_count = 0
    rparan_count = 0
    parameters = Array(Array(Token)).new
    parameter_token = Array(Token).new
    while cursor < tokens.size
      token = tokens[cursor]
      if token.type == :LPAREN
        lparen_count += 1
      elsif token.type == :COMMA
        parameters << parameter_token
        parameter_token = Array(Token).new
      elsif lparen_count > 0
        if token.type == :RPAREN
          rparan_count += 1
          if lparen_count == rparan_count
            parameters << parameter_token
            break
          end
        else
          unless token.type == :WHITESPACE || token.type == :TAB || token.type == :NEWLINE
            parameter_token << token
          end
        end
      end

      cursor += 1
    end

    parameters
  end

  def parse_annotations(tokens : Array(Token), declare_token_index : Int32)    
    skip_line = 0 
    annotation_tokens = Array(Array(Token)).new

    cursor = declare_token_index - 1
    annotation_token_last_index = -1
    last_newline_index = -1
    while cursor > 0
      token = tokens[cursor]

      if tokens[cursor].type == :NEWLINE
        skip_line += 1
        if skip_line == 1
          last_newline_index = cursor
        end
      end
      
      if skip_line == 2
        # :NEWLINE(cursor) @RequestMapping
        # :NEWLINE         public class Controller(type param)
        annotation_token_index = cursor + 1
        starts_with_at = while annotation_token_index < last_newline_index
          if tokens[annotation_token_index].type == :AT
            break true
          elsif tokens[annotation_token_index].type == :WHITESPACE || tokens[annotation_token_index].type == :TAB || tokens[annotation_token_index].type == :WHITESPACE
            annotation_token_index += 1
            next
          else
            break false
          end
        end

        if starts_with_at
          annotation_tokens << tokens[annotation_token_index..last_newline_index-1]
          skip_line = 1
          last_newline_index = cursor
        else
          break
        end
      end
      
      cursor -= 1
    end

    return annotation_tokens
  end
  
  def parse_classes(tokens : Array(Token))
    start_token_parse = false    
    class_body = Array(Token).new

    lbrace = rbrace = 0
    tokens.each do |token|
      if !start_token_parse && token.type == :CLASS && tokens[token.index+1].type == :WHITESPACE
        start_token_parse = true
        class_body = Array(Token).new        
        lbrace = rbrace = 0                        
      end
      
      if start_token_parse
        if token.type == :LBRACE
          lbrace += 1
        elsif token.type == :RBRACE
          rbrace += 1
        end
                  
        class_body << token
        if lbrace > 0 && lbrace == rbrace          
          @classes_tokens << class_body
          start_token_parse = false
        end
      end
    end
  end

  def parse_methods(class_body_tokens : Array(Token))
    # 1. Skip first line (class declaration)
    # 2. Search ":RPAREN :LBRACE" or ":RPAREN throws :IDENTIFIER :LBRACE" pattern (method body entry point)
    # 3. Get method declaration from ":NEWLINE" to ":RPAREN" (method declaration)
    # 4. Get method body from ":LBRACE" to ":RBRACE" (method body)
    # 5. Repeat 2-4 until end of class body
    methods = Array(Array(Token)).new
    method_tokens = Array(Token).new

    lbrace_count = rbrace_count = 0    
    lparen_count = rparen_count = 0

    enter_class_body = false
    enter_method_body = false
    class_body_tokens.each_index do |index|      
      token = class_body_tokens[index]
      if token.type == :NEWLINE && !enter_class_body
        # 1. Skip first line (class declaration)
        enter_class_body = true
      elsif enter_class_body && !enter_method_body           
        lbrace_count = rbrace_count = 0    
        lparen_count = rparen_count = 0
        if token.type == :LBRACE
          # 2. Search ":RPAREN :LBRACE" or ":RPAREN throws :IDENTIFIER :LBRACE" pattern (method body entry point)
          lbrace_count = 1            
          rbrace_count = 0
          lparen_count = rparen_count = 0    
          
          previous_token_index = index - 1
          has_exception = false
          while 0 < previous_token_index
            previous_token = class_body_tokens[previous_token_index]
            if previous_token.type == :RPAREN
              rparen_count = 1
              enter_method_body = true
              # 3. Get method declaration from ":NEWLINE" to ":RPAREN" (method declaration)
              method_declaration_index = previous_token_index - 1
              while 0 < method_declaration_index
                method_declaration_token = class_body_tokens[method_declaration_index]
                if method_declaration_token.type == :RPAREN
                  rparen_count += 1           
                elsif method_declaration_token.type == :LPAREN
                  lparen_count += 1
                elsif rparen_count == lparen_count && method_declaration_token.type == :NEWLINE
                  method_tokens = class_body_tokens[method_declaration_index+1..index]
                  break
                end                
                method_declaration_index -= 1
              end

              break
            elsif previous_token.type == :WHITESPACE || previous_token.type == :TAB || previous_token.type == :NEWLINE             
              previous_token_index -= 1
              next
            elsif has_exception
              break unless previous_token.type == :THROWS && previous_token.value == "throws"            
            elsif previous_token.type == :IDENTIFIER
              has_exception = true
            else
              break
            end

            previous_token_index -= 1
          end
        end
      elsif enter_method_body
        # 4. Get method body from ":LBRACE" to ":RBRACE" (method body)
        method_tokens << token
        if token.type == :RBRACE
          rbrace_count += 1
          if lbrace_count == rbrace_count
            methods << method_tokens
            method_tokens = Array(Token).new
            enter_method_body = false
          end
        elsif token.type == :LBRACE
          lbrace_count += 1
        end
      end
    end

    methods
  end

  def parse_methods22(class_body_tokens : Array(Token))
    methods = Array(Array(Token)).new
    method_tokens = Array(Token).new

    lbrace_count = rbrace_count = 0    
    lparen_count = rparen_count = 0

    method_sequence = 0
    enter_class_body = false    
    class_body_tokens.each_index do |index|
      token = class_body_tokens[index]
      if enter_class_body
        if method_sequence != 2
          if token.type == :RPAREN && method_sequence == 0            
            method_sequence = 1            
          elsif token.type == :LBRACE && method_sequence == 1
            method_sequence = 2
            lbrace_count = 1            
            rbrace_count = lparen_count = rparen_count = 0

            previous_index = index - 1
            while 0 < previous_index
              previous_token = class_body_tokens[previous_index]
              if previous_token.type == :LPAREN
                lparen_count += 1
              elsif previous_token.type == :RPAREN
                rparen_count += 1
              end
              if lparen_count == rparen_count && previous_token.type == :NEWLINE
                break                
              end
              previous_index -= 1
            end

            method_tokens = class_body_tokens[previous_index+1..index]                  
          elsif token.type == :WHITESPACE || token.type == :TAB || token.type == :NEWLINE
            next
          else
            method_tokens.clear
            method_sequence = 0
          end
        else
          if token.type == :LBRACE
            lbrace_count += 1
          elsif token.type == :RBRACE
            rbrace_count += 1
          end

          method_tokens << token
          if lbrace_count == rbrace_count
            methods << method_tokens
            method_sequence = 0
            method_tokens = Array(Token).new
          end
        end
      elsif token.type == :NEWLINE
        enter_class_body = true
      end 
    end

    methods
  end
  
  def print_tokens(tokens : Array(Token), id = "default")
    puts("================ #{id} ===================")
    tokens.each do |token|
      print(token.value)
      if id == "error"
        print("(#{token.type})")
      end
    end
    puts("\n===========================================")
  end
end

# file_path = "/Users/ksg/workspace/noir/spec/functional_test/fixtures/java_spring/src/ItemController.java"
# input = File.read(file_path)
# lexer = JavaLexer.new
# tokens = lexer.tokenize(input)
# lexer.trace
# parser = JavaParser.new
# parser.parse(tokens)
