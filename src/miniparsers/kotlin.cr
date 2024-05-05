require "../minilexers/kotlin"
require "../models/minilexer/token"

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
      #methods.each_key do |method_name|
      #  methods[method_name].params.each_with_index do |param_tokens, index|
      #    print_tokens param_tokens, "#{method_name} #{index}st param"
      #  end
      #
      #  methods[method_name].annotations.each_key do |annotation_name|
      #    annotation_model = methods[method_name].annotations[annotation_name]
      #    print_tokens annotation_model.tokens, "#{annotation_name} annotation"
      #  end
      #end
      annotations = parse_annotations(class_tokens[0].index)
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

  def parse_formal_parameters(param_start_index : Int32)
    lparen_count = 0
    rparen_count = 0
    lbrace_count = 0
    rbrace_count = 0
    parameters = Array(Array(Token)).new
    parameter = Array(Token).new
    return parameters if @tokens.size <= param_start_index

    while param_start_index < @tokens.size
      if @tokens[param_start_index].type == :TAB
        param_start_index += 1
      elsif @tokens[param_start_index].type == :NEWLINE
        param_start_index += 1
      elsif @tokens[param_start_index].type == :LPAREN
        break
      else
        return parameters
      end
    end

    cursor = param_start_index
    while cursor < @tokens.size
      token = @tokens[cursor]
      if token.type == :LPAREN
        lparen_count += 1
        if lparen_count > 1
          parameter << token
        end
      elsif token.type == :LBRACE
        lbrace_count += 1
        parameter << token
      elsif token.type == :RBRACE
        rbrace_count += 1
        parameter << token
      elsif lbrace_count == rbrace_count && lparen_count - 1 == rparen_count && token.type == :COMMA
        parameters << parameter
        parameter = Array(Token).new
      elsif lparen_count > 0
        if token.type == :RPAREN
          rparen_count += 1
          if lparen_count == rparen_count
            if parameter.size != 0
              parameters << parameter
            end
            break
          else
            parameter << token
          end
        else
          unless token.type == :TAB || token.type == :NEWLINE
            parameter << token
          end
        end
      end

      cursor += 1
    end

    parameters
  end

  def parse_annotations(declare_token_index : Int32)
    skip_line = 0
    annotation_tokens = Hash(String, AnnotationModel).new

    cursor = declare_token_index - 1
    last_newline_index = -1
    while cursor > 0
      if @tokens[cursor].type == :NEWLINE
        skip_line += 1
        if skip_line == 1
          last_newline_index = cursor
        end
      end

      if skip_line == 2
        # :NEWLINE(cursor) @RequestMapping
        # :NEWLINE         public class Controller(type param)
        annotation_token_index = cursor + 1
        is_annotation = while annotation_token_index < last_newline_index
          if @tokens[annotation_token_index].type == :LABEL_REFERENCE
            break true
          elsif !KotlinLexer::ANNOTATIONS[@tokens[annotation_token_index].value]?
            break true
          elsif @tokens[annotation_token_index].type == :TAB || @tokens[annotation_token_index].type == :NEWLINE
            annotation_token_index += 1
            next
          else
            break false
          end
        end

        if is_annotation
          annotation_name = @tokens[annotation_token_index].value
          annotation_params = parse_formal_parameters(annotation_token_index + 1)
          annotation_tokens[annotation_name] = AnnotationModel.new(annotation_name, annotation_params, @tokens[annotation_token_index..last_newline_index - 1])
          skip_line = 1
          last_newline_index = cursor
        else
          break
        end
      end

      cursor -= 1
    end

    annotation_tokens
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
          return token
        end
      end
    end

    nil
  end

  def parse_class_fields(class_start_index)
    fields = Hash(String, FieldModel).new
    params = parse_formal_parameters(class_start_index + 1)
    params.each do |param|
      init_value = ""
      val_index = -1
      assign_index = param.index { |token| token.type == :ASSIGN }
      if assign_index.nil? && param[-2].type == :COLON
        field_type = param[-1].value
        field_name = param[-3].value
        val_index = -4
      elsif assign_index && param[assign_index-2].type != :COLON
        field_type = param[assign_index-1].value
        field_name = param[assign_index-3].value
        init_value = param[assign_index+1].value
        val_index = assign_index - 4
      else
        break
      end

      modifier = "public"
      if val_index > 0
        val_or_var = param[val_index].value
        if [:PRIVATE, :PUBLIC, :PROTECTED, :INTERNAL].index(param[val_index-1].type)
          modifier = param[0].value
        end  
      elsif val_index == 0
        val_or_var = param[val_index].value
      else
        break
      end
      
      fields[field_name] = FieldModel.new(modifier, val_or_var, field_type, field_name, init_value)
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
    method_body_index = nil
    method_name = ""
    nesting = 0
  
    class_tokens.each_with_index do |token, index|
      if token.type == :FUN
        param_start_index = nil
        param = Array(Token).new
        current_params = [] of Array(Token)
        nesting = 0

        current_annotations = parse_annotations(token.index)
        method_name = class_tokens[index + 1].value if class_tokens[index + 1].type == :IDENTIFIER
        method_start_index = index

        current_params = parse_formal_parameters(token.index+2)
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