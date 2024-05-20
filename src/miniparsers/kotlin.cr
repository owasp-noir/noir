require "../minilexers/kotlin"
require "../models/minilexer/token"

BRACKET_PAIRS = {
  :LPAREN => :RPAREN,
  :RBRACE => :LBRACE,
  :LSQUARE => :RSQUARE,
  :LANGLE => :RANGLE,
  :RPAREN => :LPAREN,
  :LBRACE => :RBRACE,
  :RSQUARE => :LSQUARE,
  :RANGLE => :LANGLE
}

class KotlinParser
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
      name_token = get_class_name(class_tokens)
      next if name_token.nil?
      methods = parse_methods(class_tokens)
      annotations = parse_annotations_backwards(class_tokens[0].index)
      fields = parse_class_fields(name_token.index)
      @classes << ClassModel.new(annotations, name_token.value, fields, methods, class_tokens)
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
          if tokens[i].type != :NEWLINE
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

  def find_bracket_partner(param_start_index : Int32)
    token = @tokens[param_start_index]
    next_direction = true
    open_bracket = token.type
    close_bracket = BRACKET_PAIRS[token.type]?
    return nil if close_bracket.nil?

    if [:RPAREN, :RBRACE, :RSQUARE, :RANGLE].index(token.type)
      next_direction = false
      open_bracket = BRACKET_PAIRS[token.type]?
      close_bracket = token.type
    end

    if next_direction
      nesting = 1
      index = param_start_index + 1
      while index < @tokens.size
        token = @tokens[index]
        if token.type == open_bracket
          nesting += 1
        elsif token.type == close_bracket
          nesting -= 1
          if nesting == 0
            return index
          end
        end

        index += 1
      end
    else
      nesting = -1
      index = param_start_index - 1
      while index >= 0
        token = @tokens[index]
        if token.type == open_bracket
          nesting += 1
          if nesting == 0
            return index
          end
        elsif token.type == close_bracket
          nesting -= 1
        end

        index -= 1
      end
    end
  end

  def parse_formal_parameters(param_start_index : Int32)
    parameters = Array(Array(Token)).new
    partner_index = find_bracket_partner(param_start_index)
    if partner_index.nil?
      return parameters
    end

    parameter = Array(Token).new
    start_index = param_start_index + 1
    end_index = partner_index - 1
    if start_index > end_index
      start_index, end_index = end_index, start_index
    end

    while start_index <= end_index
      token = @tokens[start_index]
      if token.type == :COMMA
        parameters << parameter
        parameter = Array(Token).new
      elsif token.type != :TAB && token.type != :NEWLINE
        parameter << token
      end

      start_index += 1
    end

    if parameter.size > 0
      parameters << parameter
    end

    parameters
  end

  def find_annotation_end(start_index)
    if @tokens[start_index] != :ANNOTATION
      return nil
    end
    
    annotation_token = @tokens[start_index]
    annotation_name = annotation_token.value
    if ["@field", "@file", "@property", "@get", "@set", "@receiver", "@param", "@setparam", "@delegate"].index(annotation_name)
      # annotationUseSiteTarget NL* COLON NL* unescapedAnnotation
      # annotationUseSiteTarget COLON LSQUARE unescapedAnnotation+ RSQUARE
      index = start_index + 1
      while index < @tokens.size
        token = @tokens[index]
        token_value = token.value
        token_type = token.type

        if token_type == :NEWLINE
          index += 1
        elsif token_type == :COLON
          index += 1
        elsif token_type == :IDENTIFIER
          index += 1
        elsif token_type == :LANGLE
          # typeArguments
          index = find_bracket_partner(index) + 1
          if @tokens[index].type == :QUEST
            index += 1
          end
        elsif token_type == :LPAREN || token_type == :LSQUARE
          # valueArguments, arrayAccess
          index = find_bracket_partner(index) + 1
        else
          return nil
        end
      end

      return index
    elsif annotation_name.start_with?("@")
      # LabelReference (NL* DOT NL* simpleIdentifier)* (NL* typeArguments)? (NL* valueArguments)?
      # AT LSQUARE unescapedAnnotation+ RSQUARE
      index = start_index + 1
      while index < @tokens.size
        token = @tokens[index]
        token_value = token.value
        token_type = token.type

        if token_type == :NEWLINE
          index += 1
        elsif token_type == :DOT
          index += 1
        elsif token_type == :IDENTIFIER
          index += 1
        elsif token_type == :LANGLE
          # typeArguments
          index = find_bracket_partner(index) + 1
          if @tokens[index].type == :QUEST
            index += 1
          end
        elsif token_type == :LPAREN || token_type == :LSQUARE
          # valueArguments, arrayAccess
          index = find_bracket_partner(index) + 1
        else
          return nil
        end
      end
    end

    return index
  end

  def find_annotation_start(end_index)
    return nil unless end_index < @tokens.size && end_index >= 0
    cursor = end_index - 1
  
    while cursor >= 0
      token = @tokens[cursor]
      token_type = token.type
      token_value = token.value
  
      # Assume the presence of a utility method `is_annotation_token?` to determine if a token marks an annotation start
      return cursor if token_type == :ANNOTATION && is_annotation_start?(token_value)
  
      case token_type
      when :NEWLINE, :DOT, :IDENTIFIER, :COLON, :TAB
        cursor -= 1
      when :RANGLE, :RPAREN, :RSQUARE
        # If encountering a closing bracket, find its partner opening bracket
        partner = find_bracket_partner(cursor)
        return nil unless partner
        cursor = partner - 1
      else
        return nil
      end
    end
  
    nil
  end

  def is_annotation_start?(annotation_name)
    [
      "@field", "@file", "@property", "@get", "@set", "@receiver", 
      "@param", "@setparam", "@delegate"
    ].includes?(annotation_name) || annotation_name.starts_with?("@")
  end

  def parse_annotations_backwards(backward_index)
    annotation_model_map = Hash(String, AnnotationModel).new
    cursor = backward_index - 1
    declard_type = @tokens[backward_index].type
    while cursor > 0 && @tokens[cursor].type != :NEWLINE
      cursor -= 1
    end

    annotation_start_index = find_annotation_start(cursor)
    while !annotation_start_index.nil?
      annotation_token = @tokens[annotation_start_index]
      annotation_name = annotation_token.value
      annotation_end = cursor
      while annotation_end > 0 && @tokens[annotation_end].type == :NEWLINE
        annotation_end -= 1
      end
      annotation_params = [] of Array(Token)
      if @tokens[annotation_start_index+1].type == :LPAREN
        annotation_params = parse_formal_parameters(annotation_start_index + 1)
      end
      annotation_model_map[annotation_name] = AnnotationModel.new(annotation_name, annotation_params, @tokens[annotation_start_index..annotation_end])
      annotation_start_index = find_annotation_start(annotation_start_index)
    end

    return annotation_model_map
  end

  def parse_classes(tokens : Array(Token))
    start_class = false
    has_class_body = false
    class_tokens = Array(Token).new

    nesting = 0
    index = 0
    while index < tokens.size
      token = tokens[index]
      if start_class
        class_tokens << token
      end

      case token.type
      when :CLASS
        if tokens[index + 1].type == :IDENTIFIER && !start_class
          start_class = true
          nesting = 0
          class_tokens = Array(Token).new
          class_tokens << token
        end
      when :LPAREN, :LBRACE
        nesting += 1
      when :RPAREN, :RBRACE
        nesting -= 1
        if nesting == 0
          if has_class_body
            @classes_tokens << class_tokens
            start_class = false
            has_class_body = false
          else
            if start_class
              body_index = index + 1
              skip_type_identifier = false
              has_class_body = while body_index < tokens.size
                body_token = tokens[body_index]
                if body_token.type == :TAB || body_token.type == :NEWLINE
                  body_index += 1
                elsif skip_type_identifier
                  if body_token.type != :IDENTIFIER
                    break false
                  else
                    body_index += 1
                    skip_type_identifier = false
                  end
                elsif body_token.type == :COLON
                  body_index += 1
                  skip_type_identifier = true
                elsif body_token.type == :LBRACE
                  break true
                else
                  break false
                end
              end

              if !has_class_body
                @classes_tokens << class_tokens
                start_class = false
              end
            end
          end
        end
      end

      index += 1
    end
  end

  def get_class_name(tokens : Array(Token))
    has_token = false
    tokens.each do |token|
      if token.index != 0
        if token.type == :CLASS
          has_token = true
        elsif has_token && token.type == :IDENTIFIER
          return token
        end
      end
    end

    nil
  end

  def parse_class_fields(class_start_index)
    fields = Hash(String, FieldModel).new
    params = parse_formal_parameters(class_start_index + 1)
    class_name = @tokens[class_start_index].value
    params.each do |param|
      access_modifier = "public"
      val_or_var = nil
      field_type = nil
      field_name = nil
      has_type = false
      has_init_value = false
      init_value = ""
      skip_attributes = false

      index = 0
      nesting = 0
      token_size = param.size
      while index < token_size
        token = param[index]
        token_value = token.value
        token_type = token.type

        if token_type == :ANNOTATION
          skip_attributes = true
        elsif skip_attributes
          if token_type == :LPAREN
            nesting += 1
          elsif token_type == :RPAREN
            nesting -= 1
          end

          if nesting == 0
            skip_attributes = false
          end
        elsif token_value == "open"
          next
        elsif [:PRIVATE, :PUBLIC, :PROTECTED, :INTERNAL].index(token_type)
          access_modifier = token_value
        elsif token_value == "val" || token_value == "var"
          val_or_var = token_value
        elsif !val_or_var.nil? && field_name.nil?
          field_name = token_value
        elsif has_init_value
          init_value += token_value
        elsif token_type == :ASSIGN
          has_init_value = true
        elsif has_type && field_type.nil?
          field_type = token_value
        elsif token_type == :COLON
          has_type = true
        end

        index += 1
      end

      next if val_or_var.nil? || field_type.nil? || field_name.nil?
      fields[field_name] = FieldModel.new(access_modifier, val_or_var, field_type, field_name, init_value)
    end

    fields
  end

  def parse_methods(class_tokens : Array(Token))
    methods = {} of String => MethodModel
    param = Array(Token).new
    current_params = [] of Array(Token)
    current_annotations = {} of String => AnnotationModel
    method_start_index = nil
    param_start_index = nil
    method_name = ""
    nesting = 0

    class_tokens.each_with_index do |token, index|
      if token.type == :FUN
        param_start_index = nil
        param = Array(Token).new
        current_params = [] of Array(Token)
        nesting = 0

        current_annotations = parse_annotations_backwards(token.index)
        method_name = class_tokens[index + 1].value if class_tokens[index + 1].type == :IDENTIFIER
        method_start_index = index

        current_params = parse_formal_parameters(token.index + 2)
        methods[method_name] = MethodModel.new(method_name, current_params, current_annotations)
      end
    end

    methods
  end

  def print_tokens(tokens : Array(Token), id = "default", trace = false)
    puts("\n================ #{id} ===================")
    tokens.each do |token|
      print("#{token.value} ")
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

  def trace
    @classes.each do |_class|
      _class.annotations.each_key do |annotation_name|
        annotation_model = _class.annotations[annotation_name]
        print_tokens annotation_model.tokens, "#{_class.name} annotation"
      end

      puts("\n================ class #{_class.name} ==================")
      _class.fields.each_key do |field_name|
        field = _class.fields[field_name]
        puts("[Field] #{field.access_modifier} #{field.val_or_var} #{field.name}: #{field.type} = #{field.init_value}")
      end

      _class.methods.each_key do |method_name|
        _class.methods[method_name].params.each_with_index do |param_tokens, index|
          print_tokens param_tokens, "#{method_name} #{index}st param"
        end

        _class.methods[method_name].annotations.each_key do |annotation_name|
          annotation_model = _class.methods[method_name].annotations[annotation_name]
          print_tokens annotation_model.tokens, "#{method_name} method annotation"
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

    def initialize(@name, @params, @annotations)
    end
  end

  class FieldModel
    property access_modifier : String
    property type : String
    property name : String
    property val_or_var : String
    property init_value : String
    property? has_getter : Bool
    property? has_setter : Bool

    def initialize(@access_modifier, @val_or_var, @type, @name, @init_value)
      # [access_modifier] [static] [final] type name [= initial value] ;
      @has_getter = true
      @has_setter = val_or_var == "var"
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
end
