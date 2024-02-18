require "../minilexers/java"
require "../models/minilexer/token"

class JavaParser
  def initialize
    @import_statements = Array(String).new
    @classes_body_tokens = Array(Array(Token)).new
  end

  def parse(tokens : Array(Token))    
    parse_import_statements(tokens)
    parse_classes_body(tokens)
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

  def parse_classes_body(tokens : Array(Token))
    start_token_parse = false    
    class_body = Array(Token).new

    lbrace = 0
    rbrace = 0
    tokens.each do |token|
      if !start_token_parse && token.type == :AT
        start_token_parse = true
        class_body = Array(Token).new        
        lbrace = 0
        rbrace = 0
      end
      
      if start_token_parse
        if token.type == :LBRACE
          lbrace += 1
        elsif token.type == :RBRACE
          rbrace += 1
        end
                  
        class_body << token
        if lbrace > 0 && lbrace == rbrace
          print_tokens class_body
          @classes_body_tokens << class_body
          start_token_parse = false
        end
      end
    end
  end

  def parse_annotation_definitions(tokens : Array(Token))
    method_tokens = tokens.select { |token| token.type == :METHOD }
    method_tokens.each do |method_token|
      method_lines = method_token.value.split("\n")
      method_header = method_lines[0].gsub("{", "").strip
      method_body = method_lines[1..-2].join("\n").strip
      puts "Method: #{method_header}"
      puts "Body: #{method_body}"
    end
  end
  
  def print_tokens(tokens : Array(Token))
    puts "token size: #{tokens.size}"
    tokens.each do |token|
      print(token.value)
    end
    puts("\n=====================================")
  end
end

# file_path = "/Users/ksg/workspace/noir/spec/functional_test/fixtures/java_spring/src/ItemController.java"
# input = File.read(file_path)
# lexer = JavaLexer.new
# tokens = lexer.tokenize(input)
# lexer.trace
# parser = JavaParser.new
# parser.parse(tokens)