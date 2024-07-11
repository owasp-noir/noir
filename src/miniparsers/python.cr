require "../minilexers/python"
require "../models/minilexer/token"

class PythonParser
    property classes_tokens : Array(Array(Token))
    property classes : Array(ClassModel)
    property tokens : Array(Token)
    property import_statements : Array(String)
    property path : String

    def initialize(@path : String, @tokens : Array(Token))
        @import_statements = [] of String
        @classes_tokens = [] of Array(Token)
        @classes = [] of ClassModel
        parse()
    end

    def parse
        parse_import_statements(@tokens)
        parse_classes(@tokens)
        @classes_tokens.each do |class_tokens|
            name_token = get_class_name(class_tokens)
            next if name_token.nil?
            modifiers = parse_class_modifiers(name_token.index)
            methods = parse_methods(class_tokens)
            annotations = parse_annotations_backwards(class_tokens[0].index)
            fields = parse_class_parameters(name_token.index)
            parse_fields_from_class_body(name_token.index, fields, methods)
            @classes << ClassModel.new(modifiers, annotations, name_token.value, fields, methods, class_tokens)
        end
    end

    def parse_import_statements(tokens : Array(Token))
        import_tokens = tokens.select! { |token| token.type == :IMPORT }
        import_tokens.each do |import_token|
            next_token_index = import_token.index + 1
            next_token = tokens[next_token_index]
            unless next_token.nil?
                if next_token.type == :IDENTIFIER
                    import_statement = next_token.value
                    next_token_index += 1
                    while next_token_index < tokens.size && tokens[next_token_index].type == :DOT
                        next_token_index += 1
                        identifier_token = tokens[next_token_index]
                        break unless identifier_token
                        break unless identifier_token.type == :IDENTIFIER && identifier_token.value == "*"
                        import_statement += ".#{identifier_token.value}"
                        next_token_index += 1
                    end
                    @import_statements << import_statement
                end
            end
        end
    end

    def parse_classes(tokens : Array(Token))
        class_start = false
        class_tokens = [] of Token
        tokens.each do |token|
            case token.type
            when :CLASS
                class_start = true
                class_tokens = [] of Token
                class_tokens << token
            when :NEWLINE, :EOF
                @classes_tokens << class_tokens
                class_start = false
            else
                class_tokens << token if class_start
            end
        end
    end

    def get_class_name(class_tokens : Array(Token))
        class_tokens.each do |token|
            return token if token.type == :IDENTIFIER
        end
        nil
    end

    # Parse class modifiers in Python.
    def parse_class_modifiers(index : Int32)
        modifiers = [] of String
        while index >= 0
            token = @tokens[index]
            break unless token.type == :IDENTIFIER
            modifiers << token.value
            index -= 1
        end
        modifiers.reverse
    end

    # Parse methods within a class.
    def parse_methods(class_tokens : Array(Token))
        methods = [] of MethodModel
        class_tokens.each_with_index do |token, index|
            if token.type == :DEF
                method_name_token = class_tokens[index + 1] if class_tokens[index + 1]?.type == :IDENTIFIER
                parameters = parse_method_parameters(class_tokens, index + 2)
                methods << MethodModel.new(method_name_token.value, parameters)
            end
        end
        methods
    end

    # Parse decorators above functions or methods.
    def parse_annotations_backwards(backward_index : Int32)
        annotations = [] of String
        while backward_index >= 0
            token = @tokens[backward_index]
            break unless token.type == :AT
            annotation_name_token = @tokens[backward_index + 1]
            annotations << annotation_name_token.value if annotation_name_token?.type == :IDENTIFIER
            backward_index -= 2
        end
        annotations.reverse
    end

    # Parse fields from the class body.
    def parse_fields_from_class_body(index : Int32, fields : Array(FieldModel), methods : Array(MethodModel))
        # Find fields assigned directly at the class level and within the __init__ method
        @tokens.each_with_index do |token, i|
            if token.type == :IDENTIFIER && @tokens[i + 1]?.type == :ASSIGN
                field_name = token.value
                fields << FieldModel.new(field_name) # Add field to the field model
            end
        end

        parse_fields_from_init_method(methods, fields)
    end

    # Parse method parameters.
    private def parse_fields_from_init_method(methods : Array(MethodModel), fields : Array(FieldModel))
        init_method = methods.find { |method| method.name == "__init__" }
        return unless init_method

        init_method.tokens.each_with_index do |token, i|
            if token.type == :SELF && init_method.tokens[i + 1]?.type == :DOT && init_method.tokens[i + 2]?.type == :IDENTIFIER
                field_name = init_method.tokens[i + 2].value
                fields << FieldModel.new(field_name) # Add field to the field model
            end
        end
    end
end
