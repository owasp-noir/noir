require "../minilexers/java"
require "../models/minilexer/token"

class JavaParser
  property classes_tokens : Array(Array(Token))
  property classes : Array(ClassModel)
  property tokens : Array(Token)
  property import_statements : Array(String)
  property path : String

  def initialize(@path : String, @tokens : Array(Token))
    @import_statements = Array(String).new
    @classes_tokens = Array(Array(Token)).new
    @classes = Array(ClassModel).new

    parse()
  end

  def parse
    parse_import_statements(@tokens)
    parse_classes(@tokens)
    @classes_tokens.each do |class_tokens|
      name = get_class_name(class_tokens)
      methods = parse_methods(class_tokens)
      annotations = parse_annotations_backwards(@tokens, class_tokens[0].index)
      fields = parse_fields(class_tokens, methods, annotations)
      @classes << ClassModel.new(annotations, name, fields, methods, class_tokens)
    end
  end

  def get_root_source_directory(path : String, package_name : String)
    i = 0
    path = Path.new(path).parent
    while i < package_name.split(".").size
      path = path.parent
      i += 1
    end

    path
  end

  def get_package_name(tokens : Array(Token))
    package_start = false
    tokens.each_with_index do |token, index|
      if token.type == :PACKAGE
        package_start = true
        i = index + 1
        package_name = ""
        while i < tokens.size
          if tokens[i].type != :SEMI
            if tokens[i].type == :IDENTIFIER || tokens[i].type == :DOT
              package_name += tokens[i].value
            end
          else
            return package_name
          end

          i += 1
        end
        break
      end
    end

    ""
  end

  def parse_import_statements(tokens : Array(Token))
    import_tokens = tokens.select { |token| token.type == :IMPORT }
    import_tokens.each do |import_token|
      next_token_index = import_token.index + 1
      next_token = tokens[next_token_index]

      if next_token
        if next_token.type == :STATIC
          next_token_index += 1
          next_token = tokens[next_token_index]
        end
        if next_token.type == :IDENTIFIER
          import_statement = next_token.value
          next_token_index += 1

          while next_token_index < tokens.size && tokens[next_token_index].type == :DOT
            next_token_index += 1
            identifier_token = tokens[next_token_index]
            break if !identifier_token
            break if identifier_token.type != :IDENTIFIER && identifier_token.value != "*"

            import_statement += ".#{identifier_token.value}"
            next_token_index += 1
          end

          @import_statements << import_statement
        end
      end
    end
  end

  def parse_formal_parameters(tokens : Array(Token), param_start_index : Int32)
    parameters = Array(Array(Token)).new
    return parameters if tokens.size <= param_start_index

    lparen_index = param_start_index
    while lparen_index < tokens.size
      if tokens[lparen_index].type == :TAB
        lparen_index += 1
      elsif tokens[lparen_index].type == :NEWLINE
        lparen_index += 1
      elsif tokens[lparen_index].type == :LPAREN
        break
      else
        # No parameters or wrong index was given
        return parameters
      end
    end

    # Parse the formal parameters between ( and )
    lparen_count = 0
    other_open_count = 0
    cursor = lparen_index
    parameter_token = Array(Token).new # Add this line to declare the parameter_token variable
    while cursor < tokens.size
      token = tokens[cursor]
      if token.type == :LPAREN
        lparen_count += 1
        if lparen_count > 1
          parameter_token << token
        end
      elsif token.type == :LBRACE || token.type == :LBRACK || token.type == :LT
        other_open_count += 1
        parameter_token << token
      elsif token.type == :RBRACE || token.type == :RBRACK || token.type == :GT
        other_open_count -= 1
        parameter_token << token
      elsif token.type == :COMMA && other_open_count == 0 && lparen_count == 1
        parameters << parameter_token
        parameter_token = Array(Token).new
      else
        if token.type != :RPAREN
          if token.type == :TAB || token.type == :NEWLINE # Skip TAB and NEWLINE tokens
            cursor += 1
            next
          end
          parameter_token << token # Add token to the parameter token list
        else
          lparen_count -= 1
          if lparen_count == 0
            parameters << parameter_token
            break # End of the formal parameters
          else
            parameter_token << token
          end
        end
      end

      cursor += 1
    end

    parameters
  end

  def parse_annotations_backwards(tokens : Array(Token), declare_token_index : Int32)
    annotations = Hash(String, AnnotationModel).new

    # Find the closest newline before the declaration
    last_newline_index = -1
    cursor = declare_token_index - 1

    # Locate the newline token marking the end of the declaration line
    while cursor >= 0 && last_newline_index == -1
      if tokens[cursor].type == :NEWLINE
        last_newline_index = cursor
      end
      cursor -= 1
    end

    # Return empty annotations if no newline was found
    return annotations if last_newline_index == -1

    # Continue parsing annotations above the declaration line
    while cursor >= 0
      if tokens[cursor].type == :NEWLINE
        unless tokens[cursor + 1].type == :NEWLINE || tokens[cursor + 1].type == :TAB
          # Break if the next token is not an annotation start
          break if tokens[cursor + 1].type != :AT

          # Extract annotation name and parameters
          annotation_name = tokens[cursor + 2].value
          annotation_params = parse_formal_parameters(tokens, cursor + 3)

          # Store the annotation in the hash
          annotations[annotation_name] = AnnotationModel.new(
            annotation_name,
            annotation_params,
            tokens[cursor..last_newline_index - 1]
          )

          # Update the newline index to the current cursor
          last_newline_index = cursor
        end
      end
      cursor -= 1
    end

    annotations
  end

  def parse_classes(tokens : Array(Token))
    start_token_parse = false
    class_body = Array(Token).new

    lbrace = rbrace = 0
    tokens.each do |token|
      if !start_token_parse && token.type == :CLASS
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

  def get_class_name(tokens : Array(Token))
    has_token = false
    tokens.each do |token|
      if token.index != 0
        if token.type == :CLASS
          has_token = true
        elsif has_token && token.type == :IDENTIFIER
          return token.value
        end
      end
    end

    ""
  end

  def parse_fields(class_tokens : Array(Token), methods : Hash(String, MethodModel), annotations : Hash(String, AnnotationModel))
    fields = Hash(String, FieldModel).new
    class_body_start = false

    lbrace = 0
    rbrace = 0
    semi_indexs = Array(Int32).new
    class_tokens.each_with_index do |token, index|
      if token.type == :LBRACE
        lbrace += 1
      elsif token.type == :RBRACE
        rbrace += 1
      end

      if lbrace == rbrace + 1
        class_body_start = true
      elsif class_body_start && lbrace == rbrace
        break
      end

      if class_body_start && token.type == :SEMI && class_tokens[index + 1].type == :NEWLINE
        semi_indexs << index
      end
    end

    semi_indexs.each do |semi_index|
      is_method_token = false
      methods.values.each do |method|
        method_start = method.@tokens[0].index
        method_end = method.@tokens[-1].index
        is_method_token = method_start <= semi_index && semi_index <= method_end
      end

      if !is_method_token
        assign_index = nil
        field_name = ""
        field_index = semi_index
        while 0 < field_index
          field_index -= 1
          token = class_tokens[field_index]
          if token.type == :ASSIGN
            assign_index = field_index
          elsif token.type == :NEWLINE
            # [access_modifier] [static] [final] type name [= initial value] ;

            if assign_index.nil?
              field_name = class_tokens[semi_index - 1].value
            else
              field_name = class_tokens[assign_index - 1].value
            end

            line_tokens = Array(Token).new
            class_tokens[field_index + 1..semi_index - 1].each do |line_token|
              next if line_token.type == :TAB
              line_tokens << line_token
            end

            step = 0
            next if line_tokens.size == step

            is_static = false
            is_final = false
            modifier = "default"
            if [:PRIVATE, :PUBLIC, :PROTECTED, :DEFAULT].index(line_tokens[step].type)
              modifier = line_tokens[0].value
              step += 1
              next if line_tokens.size == step
            end

            if line_tokens[step].type == :STATIC
              is_static = true
              step += 1
              next if line_tokens.size == step
            end

            if line_tokens[step].type == :FINAL
              is_final = true
              step += 1
              next if line_tokens.size == step
            end

            # Only support common variable types
            if ["int", "integer", "long", "string", "char", "boolean"].index(line_tokens[step].value.downcase)
              field_type = line_tokens[step].value
              field_name = line_tokens[step + 1].value
              init_value = ""
              if step + 3 < line_tokens.size && line_tokens[step + 2].type == :ASSIGN
                line_tokens[step + 3..semi_index - 1].each do |init_token|
                  init_value += init_token.value # [TODO] currently support literal value only
                end
              end

              field = FieldModel.new(modifier, is_static, is_final, field_type, field_name, init_value)

              # getter, setter method
              has_getter = false
              has_setter = false
              pascal_field_name = field_name[0].upcase + field_name[1..]
              if methods.has_key?("get" + pascal_field_name)
                has_getter = true
              end
              if methods.has_key?("set" + pascal_field_name)
                has_setter = true
              end

              # lombok annotaitons
              if annotations.has_key?("Data")
                has_getter = true
                has_setter = true
              else
                has_getter = has_getter || annotations.has_key?("Getter")
                has_setter = has_setter || annotations.has_key?("Setter")
              end

              field.has_getter = has_getter
              field.has_setter = has_setter
              fields[field.name] = field
            end

            break
          end
        end
      end
    end

    fields
  end

  def parse_methods(class_tokens : Array(Token))
    # 1. Skip first line (class declaration)
    # 2. Search ":RPAREN :LBRACE" or ":RPAREN throws :IDENTIFIER :LBRACE" pattern (method body entry point)
    # 3. Get method declaration from ":NEWLINE" to ":RPAREN" (method declaration)
    # 4. Get method body from ":LBRACE" to ":RBRACE" (method body)
    # 5. Repeat 2-4 until end of class body
    methods = Hash(String, MethodModel).new
    method_tokens = Array(Token).new

    lbrace_count = rbrace_count = 0
    lparen_count = rparen_count = 0

    method_name = nil
    enter_class_body = false
    enter_method_body = false
    method_name_index = -1
    method_body_index = -1
    class_tokens.each_index do |index|
      token = class_tokens[index]
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
          method_body_index = index
          previous_token_index = index - 1
          has_exception = false
          while 0 < previous_token_index
            previous_token = class_tokens[previous_token_index]
            if previous_token.type == :RPAREN
              rparen_count = 1
              enter_method_body = true

              # 3. Get method declaration from ":NEWLINE" to ":RPAREN" (method declaration)
              i = previous_token_index - 1
              while 0 < i
                method_declaration_token = class_tokens[i]
                if method_declaration_token.type == :RPAREN
                  rparen_count += 1
                elsif method_declaration_token.type == :LPAREN
                  lparen_count += 1
                elsif rparen_count == lparen_count
                  if method_name == nil && method_declaration_token.type == :IDENTIFIER
                    method_name = method_declaration_token.value
                    method_name_index = i
                  elsif method_declaration_token.type == :NEWLINE
                    method_tokens = class_tokens[i + 1..index]
                    break
                  end
                end
                i -= 1
              end

              break
            elsif previous_token.type == :TAB || previous_token.type == :NEWLINE
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
            annotations = parse_annotations_backwards(class_tokens, method_name_index)
            if !method_name.nil?
              method_params = parse_formal_parameters(class_tokens, method_name_index + 1)
              method_body = class_tokens[method_body_index + 1..index - 1]
              methods[method_name] = MethodModel.new(method_name, method_params, annotations, method_tokens, method_body)
            end

            # reset
            method_tokens = Array(Token).new
            enter_method_body = false
            method_name = nil
          end
        elsif token.type == :LBRACE
          lbrace_count += 1
        end
      end
    end

    methods
  end

  def print_tokens(tokens : Array(Token), id = "default", trace = false)
    puts("\n================ #{id} ===================")
    tokens.each do |token|
      print(token.value)
      if id == "error"
        print("(#{token.type})")
      end
    end

    if trace
      puts ""
      tokens.each do |token|
        print("#{token.value}(#{token.type})")
      end
    end
  end
end

class AnnotationModel
  property name : String
  property params : Array(Array(Token))
  property tokens : Array(Token)

  def initialize(@name : String, @params : Array(Array(Token)), @tokens : Array(Token))
  end
end

class ClassModel
  property name : String
  property methods : Hash(String, MethodModel)
  property fields : Hash(String, FieldModel)
  property annotations : Hash(String, AnnotationModel)
  property tokens : Array(Token)

  def initialize(@annotations, @name, @fields, @methods, @tokens : Array(Token))
  end
end

class MethodModel
  property name : String
  property params : Array(Array(Token))
  property annotations : Hash(String, AnnotationModel)
  property tokens : Array(Token)
  property body : Array(Token)

  def initialize(@name, @params, @annotations, @tokens, @body)
  end
end

class FieldModel
  property access_modifier : String
  property? is_static : Bool
  property? is_final : Bool
  property type : String
  property name : String
  property init_value : String
  property? has_getter : Bool
  property? has_setter : Bool

  def initialize(@access_modifier, @is_static, @is_final, @type, @name, @init_value)
    # [access_modifier] [static] [final] type name [= initial value] ;
    @has_getter = false
    @has_setter = false
  end

  def has_getter=(value : Bool)
    @has_getter = value
  end

  def has_setter=(value : Bool)
    @has_setter = value
  end

  def to_s
    l = @access_modifier + " "
    if @is_static
      l += "static "
    end

    if @is_final
      l += "final "
    end

    l += "#{@type} #{@name}"
    if @init_value != ""
      l += " = \"#{@init_value}\""
    end

    if @has_getter
      l += " (has_getter)"
    end
    if @has_setter
      l += " (has_setter)"
    end

    l
  end
end
