require "../minilexers/python"
require "../models/minilexer/token"

class PythonParser
    property tokens : Array(Token)
    property path : String

    def initialize(@path : String, @tokens : Array(Token), @parser_map : Hash(String, PythonParser), @visited : Array(String) = Array(String).new)
        @import_statements = Hash(String, ImportModel).new
        @global_variables = Hash(String, GlobalVariables).new
        @basedir = File.dirname(@path)
        @is_package_file = File.exists?(File.dirname(@path) + "/__init__.py")
        while @basedir != "" && File.exists?(@basedir + "/__init__.py")
            @basedir = File.dirname(@basedir)
        end

        @debug = false
        @visited << path
        parse
    end

    def parse
        parse_import_statements(@tokens)        
        parse_global_variables()
    end

    # Create a parser for the given path
    def create_parser(path : Path, content : String = "") : PythonParser
        if content == ""
            content = File.read(path, encoding: "utf-8", invalid: :skip)
        end

        lexer = PythonLexer.new
        tokens = lexer.tokenize(content)
        parser = PythonParser.new(path.to_s, tokens, @parser_map, @visited.dup)
        parser
    end

    # Get the parser for the given path
    def get_parser(path : Path) : PythonParser
        if @parser_map.has_key?(path.to_s)
            return @parser_map[path.to_s]
        end

        parser = create_parser(path)
        @parser_map[path.to_s] = parser
        parser
    end

    def parse_import_statements(tokens : Array(Token))
        import_statements = Array(Array(String)).new
        index = 0
        while index < tokens.size
            code_start = index == 0 || tokens[index - 1].type == :NEWLINE || tokens[index - 1].type == :INDENT
            unless code_start
                index += 1
                next
            end

            from_strings = Array(String).new
            sindex = index
            if tokens[index].type == :FROM
                index += 1
                while tokens[index].type != :IMPORT && tokens[index].type != :EOF
                    if from_strings.size > 0
                        if tokens[index].type == :DOT
                            index += 1
                            next
                        end
                    else
                        if tokens[index].type == :DOT
                            if index + 1 < tokens.size && tokens[index+1].type == :DOT
                                from_strings << ".."
                                index += 2
                            else
                                from_strings << "."
                                index += 1
                            end
                            next
                        end
                    end

                    from_strings << tokens[index].value
                    index += 1
                end
            end

            if tokens[index].type == :IMPORT
                index += 1
                import_strings = from_strings.dup
                while tokens[index].type != :NEWLINE && tokens[index].type != :EOF
                    if tokens[index].type == :COMMA
                        import_strings = from_strings.dup
                        index += 1
                        next
                    elsif tokens[index].type == :DOT
                        index += 1
                        next
                    elsif tokens[index].type == :LPAREN
                        index += 1
                        next
                    elsif tokens[index].type == :RPAREN
                        index += 1
                        next
                    end

                    # Check if the import statement has an alias
                    import_name = tokens[index].value
                    if tokens[index + 1].type != :EOF && tokens[index + 1].type == :AS
                        as_name = tokens[index+2].value
                        index += 2
                        import_strings << import_name + " as " + as_name
                        if from_strings.size > 0
                            import_statements << import_strings
                        end
                    else
                        # No alias
                        import_strings << import_name
                        if from_strings.size > 0
                            import_statements << import_strings
                        end
                    end

                    index += 1
                end

                if from_strings.size == 0
                    # No from statement, so add the import statement
                    import_statements << import_strings
                end
            end

            index += 1
        end
        
        import_statements.each do |import_statement|
            @debug = false
            if import_statement.size == 2
                if import_statement[0] == "." && import_statement[1] == "models"
                    @debug = true
                end
            end
            
            name = import_statement[-1]

            # Check if the name has an alias
            as_name = nil
            if name.includes?(" as ")
                name, as_name = name.split(" as ") # Set as_name
                import_statement[-1] = name # Remove the alias part
            end
            
            path = nil
            pypath = nil
            remain_import_parts = false
            package_dir = @basedir
            if import_statement[0] == "."
                package_dir = File.dirname(@path)
                import_statement.shift
            end
            if import_statement.size == 2 && import_statement[0] == "models"
                @debug=true
            end
            import_statement.each_with_index do |import_part, index|
                path = File.join(package_dir, import_part)
                # Order of checking is important
                if File.directory?(path)
                    package_dir = path
                elsif File.exists?(path + ".py")
                    pypath = path + ".py"
                    if index != import_statement.size - 1
                        remain_import_parts = true
                    end
                    break
                elsif package_dir != @basedir && File.exists?(File.join(package_dir, "__init__.py"))
                    pypath = File.join(package_dir, "__init__.py")
                    if index != import_statement.size - 1
                        remain_import_parts = true
                    end
                    break
                else
                    pypath = nil
                    break
                end
            end

            unless as_name.nil?
                name = as_name
            end

            unless pypath.nil?
                if @visited.includes?(pypath)
                    next
                end
                if name == "*"
                    parser = get_parser(Path.new(pypath))
                    @global_variables.merge!(parser.@global_variables)
                else
                    parser = get_parser(Path.new(pypath))
                    if !remain_import_parts && !pypath.ends_with?("__init__.py")                       
                        parser.@global_variables.each do |key, value|
                            @global_variables["#{name}.#{key}"] = value
                        end
                    elsif parser.@global_variables.has_key?(name)
                        @global_variables[name] = parser.@global_variables[name]                        
                    end
                end
            end
        end
    end

    def parse_global_variables()
        index = 0
        while index < tokens.size
            if (index == 0 || tokens[index - 1].type == :NEWLINE) && index+3 < tokens.size
                type = nil
                if tokens[index].type == :IDENTIFIER && tokens[index+1].type == :COLON && tokens[index+3].type == :ASSIGN
                    name = tokens[index].value
                    type = tokens[index+2].value
                    value = extract_assign_data(index+4)[1]
                elsif tokens[index].type == :IDENTIFIER && tokens[index+1].type == :ASSIGN
                    name = tokens[index].value
                    t = extract_assign_data(index+2)
                    type, value = t[0], t[1]
                    # Check if the type is a direct function or class, then get the name of the function or class
                    if type.nil? && tokens[index+2].type == :IDENTIFIER                        
                        _type = ""
                        while tokens[index+2].type == :IDENTIFIER || tokens[index+2].type == :DOT
                            _type += tokens[index+2].value
                            index += 1
                        end
                        if tokens[index+2].type == :LPAREN
                            type = _type
                        end                        
                    end
                else
                    index += 1
                    next
                end

                @global_variables[name] = GlobalVariables.new(name, type, value)
            end
            index += 1
        end
    end

    # Normalize the string or fstring
    def normallize(index) : String
        if @tokens[index].type == :STRING
            str = @tokens[index].value[1..-2]
            return str
        elsif @tokens[index].type == :FSTRING
            str = @tokens[index].value[1..-2]
            str = str.gsub(/\{[a-zA-Z_]\w*\}/) do |match|
                key = match[1..-2]
                @global_variables.has_key?(key) ? @global_variables[key] : match
            end

            return str
        end

        @tokens[index].value
    end

    def extract_assign_data(index) : Tuple(String | Nil, String)
        rawdata = ""
        variable_type = nil # unknown
        sindex = index
        lparen = 0
        while index < @tokens.size
            token_type = @tokens[index].type
            token_value = @tokens[index].value
            if token_type == :LPAREN
                lparen += 1
                rawdata += token_value
            elsif lparen > 0
                rawdata += token_value
                if token_type == :RPAREN
                    lparen -= 1
                    if lparen == 0                  
                        break
                    end
                end
            elsif token_type == :NEWLINE
                break
            elsif token_type == :COMMENT
                index += 1
                next
            elsif sindex == index
                # Start of the assignment
                if token_type == :STRING || token_type == :FSTRING
                    return Tuple.new("str", normallize(index))
                else
                    rawdata += token_value
                end
            else
                rawdata += token_value
            end
            index += 1
        end

        rawdata = rawdata.strip
        if @global_variables.has_key?(rawdata)
            # Check if the rawdata is a global variable
            gv = @global_variables[token_value]
            return Tuple.new(gv.type, gv.value)
        end
        
        # Check if the rawdata is an instance variable
        instance_parts = rawdata.split(".")
        if instance_parts.size > 1
            instance = instance_parts[0]
            if @global_variables.has_key?(instance)
                gv = @global_variables[instance]
                gv_type = gv.type
                if gv_type
                    variable_type = gv_type + "." + instance_parts[1].split("(")[0]
                end
            end
        end

        Tuple.new(variable_type, rawdata)
    end

    def print_line(index)
        while index < @tokens.size
            break if @tokens[index].type == :NEWLINE
            print(@tokens[index].to_s, " ")
            index += 1
        end
        puts ""
    end

    def debug_print(s)
        if @debug
            puts s
        end
    end

    # Class to model annotations
    class ImportModel
        property name : String
        property path : String | Nil
        property as_name : String | Nil

        def initialize(@name : String, @path : String | Nil, @as_name : String | Nil)
        end

        def to_s
            if @path.nil?
                "#{@name} from {unknown}"
            elsif @as_name.nil?
                "#{@name} from #{@path}"
            else
                "#{@name} from #{@path} as #{@as_name}"
            end
        end
    end

    class GlobalVariables
        property name : String
        property type : String | Nil
        property value : String

        def initialize(@name : String, @type : String | Nil, @value : String)
        end

        def to_s
            if @type.nil?
                "#{@name} = #{@value}"
            else
                "#{@name} : #{@type} = #{@value}"
            end
        end
    end
end
