require "../../models/analyzer"
require "../../miniparsers/import_graph"
require "json"

module Analyzer::Python
  class PythonEngine < Analyzer
    # HTTP method names commonly used in REST APIs
    HTTP_METHODS = ["get", "post", "put", "patch", "delete", "head", "options", "trace"]
    # Indentation size in spaces; different sizes can cause analysis issues
    INDENTATION_SIZE = 4
    # Regex for valid Python variable names
    PYTHON_VAR_NAME_REGEX = /[a-zA-Z_][a-zA-Z0-9_]*/
    # Regex for valid Python module names
    DOT_NATION = /[a-zA-Z_][a-zA-Z0-9_.]*/

    # Parses the definition of a function from the source lines starting at a given index
    def parse_function_def(source_lines : Array(::String), start_index : Int32) : FunctionDefinition?
      parameters = [] of FunctionParameter
      def_line = source_lines[start_index]
      return unless def_line.includes?("def ")

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

    # Resolve every `import` and `from … import …` in the file to
    # `{name => {filepath, package_type}}`. Thin delegator over
    # `Noir::ImportGraph::Python.find_imported_modules` so future
    # Python analyzers (or new tagger logic) can call the resolver
    # directly without going through `PythonEngine`.
    def find_imported_modules(app_base_path : ::String, file_path : ::String, content : ::String? = nil) : Hash(::String, Tuple(::String, Int32))
      Noir::ImportGraph::Python.find_imported_modules(app_base_path, file_path, content)
    end

    # See `find_imported_modules` — same delegator.
    def find_imported_package(package_path : ::String, dotted_as_names : ::String) : Array(Tuple(::String, ::String, Int32))
      Noir::ImportGraph::Python.find_imported_package(package_path, dotted_as_names)
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
    def parse_code_block(data : ::String | Array(::String), after : Regex? = nil) : ::String?
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
        return if line_size == lines.size
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
      return data if data.numeric?

      # Check if the data is a string
      if data.size != 0
        if data[0] == data[-1] && data[0].in?('"', '\'')
          return data[1..-2]
        end
      end

      data
    end

    # `PackageType::FILE` / `PackageType::CODE` constants are now
    # canonical at `Noir::ImportGraph::Python::PackageType`. Aliasing
    # the inner module keeps `PackageType::FILE`-style references in
    # subclasses working without a sweeping rename.
    alias PackageType = Noir::ImportGraph::Python::PackageType

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
