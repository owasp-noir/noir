require "../../models/analyzer"
require "json"

class AnalyzerPython < Analyzer
  HTTP_METHOD_NAMES          = ["get", "post", "put", "patch", "delete", "head", "options", "trace"]
  INDENT_SPACE_SIZE          = 4 # Different indentation sizes can result in code analysis being disregarded
  REGEX_PYTHON_VARIABLE_NAME = "[a-zA-Z_][a-zA-Z0-9_]*"

  def parse_function_definition(source_lines : Array(String), start_index : Int) : FunctionDefinition | Nil
    params = [] of FunctionParameter
    defline = source_lines[start_index]
    if !defline.includes?("def ")
      return nil
    end

    name = defline.split("def ", 2)[1].split("(", 2)[0].strip
    param_codeline = defline.split("(", 2)[1]

    index = 0

    parameter_name = ""
    parameter_type = ""
    parameter_default = ""

    is_option_token = false
    is_default_token = false
    square_bracket = 0
    open_parentheses = 1

    line_index = start_index
    while open_parentheses != 0
      while index < param_codeline.size
        chr = param_codeline[index]
        if chr == '['
          square_bracket += 1
        elsif chr == ']'
          square_bracket -= 1
        elsif square_bracket == 0
          if chr == '('
            open_parentheses += 1
          elsif open_parentheses == 1 && chr == '='
            is_default_token = true
            index += 1
            next
          elsif open_parentheses == 1 && chr == ','
            params << FunctionParameter.new(parameter_name.strip,
              parameter_type.strip,
              parameter_default.strip)

            parameter_name = ""
            parameter_type = ""
            parameter_default = ""
            is_option_token = false
            is_default_token = false
            index += 1
            next
          elsif chr == ')'
            open_parentheses -= 1
            if open_parentheses == 0
              if parameter_name.size != 0
                params << FunctionParameter.new(parameter_name.strip,
                  parameter_type.strip,
                  parameter_default.strip)
              end

              break
            end
          elsif chr == ':'
            is_option_token = true
            index += 1
            next
          end
        end

        if is_default_token
          parameter_default += chr
        elsif is_option_token
          parameter_type += chr
        else
          parameter_name += chr
        end

        index += 1
      end

      line_index += 1
      if line_index < source_lines.size
        param_codeline = source_lines[line_index]
        index = 0
        next
      end

      break
    end

    FunctionDefinition.new(name, params)
  end

  def find_imported_modules(app_base_path : String, file_path : String, content : String | Nil = nil) : Hash(String, Tuple(String, Int32))
    # If content is not provided, read it from the file
    if content.nil?
      content = File.read(file_path, encoding: "utf-8", invalid: :skip)
    end

    file_base_path = file_path
    if file_path.ends_with? ".py"
      file_base_path = File.dirname(file_path)
    end

    import_map = {} of String => Tuple(String, Int32)

    offset = 0
    content.each_line do |line|
      package_path = app_base_path
      _from = ""
      _imports = ""

      # Check if the line starts with "from" or "import"
      if line.starts_with?("from")
        line.scan(/from\s*([^'"\s\\]*)\s*import\s*(.*)/) do |match|
          next if match.size != 3
          _from = match[1]
          _imports = match[2]
        end
      elsif line.starts_with?("import")
        line.scan(/import\s*([^'"\s\\]*)/) do |match|
          next if match.size != 2
          _imports = match[1]
        end
      end

      unless _imports.empty?
        round_bracket_index = line.index('(')
        if !round_bracket_index.nil?
          # Parse 'import (\n a,\n b,\n c)' pattern
          index = offset + round_bracket_index + 1
          while index < content.size && content[index] != ')'
            index += 1
          end
          _imports = content[(offset + round_bracket_index + 1)..(index - 1)].strip
        end

        # Handle relative paths
        if _from.starts_with?("..")
          package_path = File.join(file_base_path, "..")
          _from = _from[2..]
        elsif _from.starts_with?(".")
          package_path = file_base_path
          _from = _from[1..]
        end

        _imports.split(",").each do |_import|
          _import = _import.strip
          if _import.starts_with?("..")
            package_path = File.join(file_base_path, "..")
          elsif _import.starts_with?(".")
            package_path = file_base_path
          end

          dotted_as_names = _import
          if _from != ""
            dotted_as_names = _from + "." + _import
          end

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

  def find_imported_package(package_path : String, dotted_as_names : String) : Array(Tuple(String, String, Int32))
    package_map = Array(Tuple(String, String, Int32)).new

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
        _import = name.strip
        next if _import.empty?

        _alias = nil
        if _import.includes?(" as ")
          _import, _alias = _import.split(" as ")
        end

        package_type = File.exists?(File.join(package_path, "#{_import}.py")) ? PackageType::FILE : PackageType::CODE

        if !_alias.nil?
          package_map << {_alias, py_path, package_type}
        else
          package_map << {_import, py_path, package_type}
        end
      end
    end

    package_map
  end

  def find_json_params(codeblock_lines : Array(String), json_variable_names : Array(String)) : Array(Param)
    params = [] of Param

    codeblock_lines.each do |codeblock_line|
      json_variable_names.each do |json_variable_name|
        matches = codeblock_line.scan(/[^a-zA-Z_]#{json_variable_name}\[[rf]?['"]([^'"]*)['"]\]/)
        if matches.size == 0
          matches = codeblock_line.scan(/[^a-zA-Z_]#{json_variable_name}\.get\([rf]?['"]([^'"]*)['"]/)
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

  def parse_function_or_class(data : String | Array(String), after : Regex | Nil = nil) : String | Nil
    content = ""
    lines = [] of String
    if data.is_a?(String)
      lines = data.split("\n")
      content = data
    else
      lines = data
      content = data.join("\n")
    end

    # Remove lines before the "after" line
    if !after.nil?
      line_size = lines.size
      lines.each_with_index do |line, index|
        if line.starts_with?(after)
          lines = lines[index..]
          content = lines.join("\n")
          break
        end
      end

      # If no line starts with "after", return nil
      if line_size == lines.size
        return nil
      end
    end

    # Infer indentation size
    indent_size = 0
    if lines.size > 0
      while indent_size < lines[0].size && lines[0][indent_size] == ' '
        # Only spaces, no tabs
        indent_size += 1
      end

      indent_size += INDENT_SPACE_SIZE
    end

    # Parse function or class codeblock
    if indent_size > 0
      double_quote_open, single_quote_open = [false] * 2
      double_comment_open, single_comment_open = [false] * 2
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

          # [TODO] Remove comments on codeblock
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

  def return_literal_value(data : String) : String
    # is numeric
    if data.numeric?
      data
    else
      # is string
      if data.size != 0
        if data[0] == data[-1] && ['"', '\''].includes? data[0]
          data = data[1..-2]
          data
        end
      end
    end

    ""
  end
end

module PackageType
  FILE = 0
  CODE = 1
end

class FunctionParameter
  @name = ""
  @type = ""
  @default = ""

  def initialize(name, type, default)
    @name = name
    @type = type
    @default = default
  end

  def name
    @name
  end

  def type
    @type
  end

  def default
    @default
  end

  def to_s
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

  def name=(name)
    @name = name
  end

  def type=(type)
    @type = type
  end

  def default=(default)
    @default = default
  end
end

class FunctionDefinition
  @name = ""
  @params = [] of FunctionParameter

  def initialize(name, params)
    @name = name
    @params = params
  end

  def params
    @params
  end

  def add_parameter(param)
    @params << param
  end
end
