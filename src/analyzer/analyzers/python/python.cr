require "../../../models/analyzer"
require "json"

module Analyzer::Python
  class Python < Analyzer
    # HTTP method names commonly used in REST APIs
    HTTP_METHODS = ["get", "post", "put", "patch", "delete", "head", "options", "trace"]
    # Indentation size in spaces; different sizes can cause analysis issues
    INDENTATION_SIZE = 4
    # Regex for valid Python variable names
    PYTHON_VAR_NAME_REGEX = /[a-zA-Z_][a-zA-Z0-9_]*/
    # Regex for valid Python module names
    DOT_NATION = /[a-zA-Z_][a-zA-Z0-9_.]*/

    # Parses the definition of a function from the source lines starting at a given index
    def parse_function_def(source_lines : Array(::String), start_index : Int32) : FunctionDefinition | Nil
      parameters = [] of FunctionParameter
      def_line = source_lines[start_index]
      return nil unless def_line.includes?("def ")

      # Extract the function name and parameter line
      name = def_line.split("def ", 2)[1].split("(", 2)[0].strip
      param_line = def_line.split("(", 2)[1]

      index = 0
      param_name = ""
      param_type = ""
      param_default = ""

      is_option = false
      is_default = false
      bracket_count = 0
      parentheses_count = 1

      line_index = start_index
      # Iterate over the parameter line to parse each parameter
      while parentheses_count != 0
        while index < param_line.size
          char = param_line[index]
          if char == '['
            bracket_count += 1
          elsif char == ']'
            bracket_count -= 1
          elsif bracket_count == 0
            if char == '('
              parentheses_count += 1
            elsif parentheses_count == 1 && char == '='
              is_default = true
              index += 1
              next
            elsif parentheses_count == 1 && char == ','
              parameters << FunctionParameter.new(param_name.strip, param_type.strip, param_default.strip)

              param_name = ""
              param_type = ""
              param_default = ""
              is_option = false
              is_default = false
              index += 1
              next
            elsif char == ')'
              parentheses_count -= 1
              if parentheses_count == 0
                if param_name.size != 0
                  parameters << FunctionParameter.new(param_name.strip, param_type.strip, param_default.strip)
                end
                break
              end
            elsif char == ':'
              is_option = true
              index += 1
              next
            end
          end

          if is_default
            param_default += char
          elsif is_option
            param_type += char
          else
            param_name += char
          end

          index += 1
        end

        line_index += 1
        if line_index < source_lines.size
          param_line = source_lines[line_index]
          index = 0
          next
        end

        break
      end

      FunctionDefinition.new(name, parameters)
    end

    # Finds all the modules imported in a given Python file
    def find_imported_modules(app_base_path : ::String, file_path : ::String, content : ::String? = nil) : Hash(::String, Tuple(::String, Int32))
      # If content is not provided, read it from the file
      content = File.read(file_path, encoding: "utf-8", invalid: :skip) if content.nil?

      file_base_path = file_path
      file_base_path = File.dirname(file_path) if file_path.ends_with? ".py"

      import_map = Hash(::String, Tuple(::String, Int32)).new
      offset = 0
      content.each_line do |line|
        package_path = app_base_path
        from_import = ""
        imports = ""

        # Check if the line starts with "from" or "import"
        if line.starts_with?("from")
          line.scan(/from\s*([^'"\s\\]*)\s*import\s*(.*)/) do |match|
            next if match.size != 3
            from_import = match[1]
            imports = match[2]
          end
        elsif line.starts_with?("import")
          line.scan(/import\s*([^'"\s\\]*)/) do |match|
            next if match.size != 2
            imports = match[1]
          end
        end

        unless imports.empty?
          round_bracket_index = line.index('(')
          if !round_bracket_index.nil?
            # Parse 'import (\n a,\n b,\n c)' pattern
            index = offset + round_bracket_index + 1
            while index < content.size && content[index] != ')'
              index += 1
            end
            imports = content[(offset + round_bracket_index + 1)..(index - 1)].strip
          end

          # Handle relative paths
          if from_import.starts_with?("..")
            package_path = File.join(file_base_path, "..")
            from_import = from_import[2..]
          elsif from_import.starts_with?(".")
            package_path = file_base_path
            from_import = from_import[1..]
          end

          imports.split(",").each do |import|
            import = import.strip
            if import.starts_with?("..")
              package_path = File.join(file_base_path, "..")
            elsif import.starts_with?(".")
              package_path = file_base_path
            end

            dotted_as_names = import
            dotted_as_names = "#{from_import}.#{import}" unless from_import.empty?

            # Create package map (Hash[name => filepath, ...])
            import_package_map = find_imported_package(package_path, dotted_as_names)
            next if import_package_map.empty?
            import_package_map.each do |name, filepath, package_type|
              import_map[name] = {filepath, package_type}
            end
          end
        end

        offset += line.size + 1
      end

      import_map
    end

    # Finds the package path for imported modules
    def find_imported_package(package_path : ::String, dotted_as_names : ::String) : Array(Tuple(::String, ::String, Int32))
      package_map = Array(Tuple(::String, ::String, Int32)).new

      py_path = ""
      is_positive_travel = false
      dotted_as_names_split = dotted_as_names.split(".")

      dotted_as_names_split.each_with_index do |names, index|
        travel_package_path = File.join(package_path, names)

        py_guess = "#{travel_package_path}.py"
        if File.directory?(travel_package_path)
          package_path = travel_package_path
          is_positive_travel = true
        elsif dotted_as_names_split.size - 2 <= index && File.exists?(py_guess)
          py_path = py_guess
          is_positive_travel = true
        else
          break
        end
      end

      if is_positive_travel
        names = dotted_as_names_split[-1]
        names.split(",").each do |name|
          import = name.strip
          next if import.empty?

          alias_name = nil
          if import.includes?(" as ")
            import, alias_name = import.split(" as ")
          end

          package_type = File.exists?(File.join(package_path, "#{import}.py")) ? PackageType::FILE : PackageType::CODE

          if !alias_name.nil?
            package_map << {alias_name, py_path, package_type}
          else
            package_map << {import, py_path, package_type}
          end
        end
      end

      package_map
    end

    # Finds all parameters in JSON objects within a given code block
    def find_json_params(codeblock_lines : Array(::String), json_var_names : Array(::String)) : Array(Param)
      params = [] of Param

      codeblock_lines.each do |codeblock_line|
        json_var_names.each do |json_var_name|
          matches = codeblock_line.scan(/[^a-zA-Z_]#{json_var_name}\[[rf]?['"]([^'"]*)['"]\]/)
          if matches.size == 0
            matches = codeblock_line.scan(/[^a-zA-Z_]#{json_var_name}\.get\([rf]?['"]([^'"]*)['"]/)
          end

          if !matches.nil?
            matches.each do |match|
              if match.size > 0
                params << Param.new(match[1], "", "json")
              end
            end
          end
        end
      end

      params
    end

    # Parses a function or class definition from a string or an array of strings
    def parse_code_block(data : ::String | Array(::String), after : Regex | Nil = nil) : ::String | Nil
      content = ""
      lines = [] of ::String
      if data.is_a?(::String)
        lines = data.split("\n")
        content = data
      else
        lines = data
        content = data.join("\n")
      end

      # Remove lines before the "after" line if provided
      unless after.nil?
        line_size = lines.size
        lines.each_with_index do |line, index|
          if line.starts_with?(after)
            lines = lines[index..]
            content = lines.join("\n")
            break
          end
        end

        # If no line starts with "after", return nil
        return nil if line_size == lines.size
      end

      # Infer indentation size
      indent_size = 0
      if lines.size > 0
        while indent_size < lines[0].size && lines[0][indent_size] == ' '
          # Only spaces, no tabs
          indent_size += 1
        end

        indent_size += INDENTATION_SIZE
      end

      # Parse function or class code block
      if indent_size > 0
        double_quote_open, single_quote_open = [false, false]
        double_comment_open, single_comment_open = [false, false]
        end_index = lines[0].size + 1
        lines[1..].each do |line|
          line_index = 0
          clear_line = line
          while line_index < line.size
            if line_index < line.size - 2
              if !single_quote_open && !double_quote_open
                if !double_comment_open && line[line_index..line_index + 2] == "'''"
                  single_comment_open = !single_comment_open
                  line_index += 3
                  next
                elsif !single_comment_open && line[line_index..line_index + 2] == "\"\"\""
                  double_comment_open = !double_comment_open
                  line_index += 3
                  next
                end
              end
            end

            if !single_comment_open && !double_comment_open
              if !single_quote_open && line[line_index] == '"' && line[line_index - 1] != '\\'
                double_quote_open = !double_quote_open
              elsif !double_quote_open && line[line_index] == '\'' && line[line_index - 1] != '\\'
                single_quote_open = !single_quote_open
              elsif !single_quote_open && !double_quote_open && line[line_index] == '#' && line[line_index - 1] != '\\'
                clear_line = line[..(line_index - 1)]
                break
              end
            end

            line_index += 1
          end

          open_status = single_comment_open || double_comment_open || single_quote_open || double_quote_open
          if clear_line[0..(indent_size - 1)].strip == "" || open_status
            end_index += line.size + 1
          else
            break
          end
        end

        end_index -= 1
        return content[..end_index].strip
      end

      nil
    end

    # Returns the literal value from a string if it represents a number or a quoted string
    def return_literal_value(data : ::String) : ::String
      # Check if the data is numeric
      if data.numeric?
        data
      else
        # Check if the data is a string
        if data.size != 0
          if data[0] == data[-1] && ['"', '\''].includes? data[0]
            data = data[1..-2]
            data
          end
        end
      end

      ""
    end

    module PackageType
      FILE = 0
      CODE = 1
    end

    class FunctionParameter
      @name : ::String
      @type : ::String
      @default : ::String

      def initialize(name : ::String, type : ::String, default : ::String)
        @name = name
        @type = type
        @default = default
      end

      def name : ::String
        @name
      end

      def type : ::String
        @type
      end

      def default : ::String
        @default
      end

      def to_s : ::String
        if @type.size != 0
          if @default.size != 0
            "Name(#{@name}): Type(#{@type}) = Default(#{@default})"
          else
            "Name(#{@name}): Type(#{@type})"
          end
        else
          "Name(#{@name})"
        end
      end

      def name=(name : ::String)
        @name = name
      end

      def type=(type : ::String)
        @type = type
      end

      def default=(default : ::String)
        @default = default
      end
    end

    class FunctionDefinition
      @name : ::String
      @params : Array(FunctionParameter)

      def initialize(name : ::String, params : Array(FunctionParameter))
        @name = name
        @params = params
      end

      def params : Array(FunctionParameter)
        @params
      end

      def add_parameter(param : FunctionParameter)
        @params << param
      end
    end
  end
end
