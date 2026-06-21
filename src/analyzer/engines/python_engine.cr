require "../../models/analyzer"
require "../../miniparsers/import_graph"
require "../../miniparsers/python_callee_extractor"
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

    # Standard Python/pytest/unittest test-file conventions. A file
    # under any of these patterns ships with `python -m pytest` or
    # `python -m unittest` and never serves real traffic in
    # production. Centralized so every analyzer can opt in via
    # `next if python_test_path?(path)`.
    #
    #   * `/tests/`, `/test/` — pytest discovery defaults and common
    #                           framework fixture packages (Django,
    #                           Litestar, FastAPI all use variants)
    #   * `tests.py`         — the legacy Django per-app test module
    #   * `test_*.py`        — unittest / pytest default discovery
    #   * `*_test.py`        — pytest-go style suffix (rare in Python,
    #                          but cheap to include)
    def self.python_test_path?(path : String, base_path : String? = nil) : Bool
      relative_path = path_for_test_convention_match(path, base_path)
      return true if relative_path.includes?("/tests/")
      return true if relative_path.starts_with?("tests/")
      return true if relative_path.includes?("/test/")
      return true if relative_path.starts_with?("test/")
      return true if relative_path.includes?("/test_utils/")
      return true if relative_path.starts_with?("test_utils/")
      base = File.basename(path)
      return true if base == "tests.py"
      return true if base.starts_with?("test_") && base.ends_with?(".py")
      base.ends_with?("_test.py")
    end

    protected def python_base_path_for(path : String) : String
      configured_base_for(path)
    end

    protected def python_test_path?(path : String) : Bool
      PythonEngine.python_test_path?(path, python_base_path_for(path))
    end

    private def self.path_for_test_convention_match(path : String, base_path : String?) : String
      Noir::PathScope.relative_under(path, base_path)
    end

    # Parses the definition of a function from the source lines starting at a given index
    def parse_function_def(source_lines : Array(::String), start_index : Int32) : FunctionDefinition?
      parameters = [] of FunctionParameter
      def_line = source_lines[start_index]?
      # A real `def`/`async def` header always contains `(`; requiring it (and
      # guarding the out-of-range index) prevents `split("(", 2)[1]` IndexError
      # when a bogus fallback line merely contains the substring "def ".
      return unless def_line && def_line.includes?("def ") && def_line.includes?("(")

      # Extract the function name and parameter line
      name = def_line.split("def ", 2)[1].split("(", 2)[0].strip
      param_line = def_line.split("(", 2)[1]

      index = 0
      # Accumulate field text in builders rather than `String += Char`: a single
      # giant parameter default (e.g. a multi-kilobyte literal) otherwise makes the
      # per-character append O(n²) and can hang the scan.
      param_name = String::Builder.new
      param_type = String::Builder.new
      param_default = String::Builder.new

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
              parameters << FunctionParameter.new(param_name.to_s.strip, param_type.to_s.strip, param_default.to_s.strip)

              param_name = String::Builder.new
              param_type = String::Builder.new
              param_default = String::Builder.new
              is_option = false
              is_default = false
              index += 1
              next
            elsif char == ')'
              parentheses_count -= 1
              if parentheses_count == 0
                name_text = param_name.to_s
                if name_text.bytesize != 0
                  parameters << FunctionParameter.new(name_text.strip, param_type.to_s.strip, param_default.to_s.strip)
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
            param_default << char
          elsif is_option
            param_type << char
          else
            param_name << char
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

      # Hoisted out of the per-line loop: an interpolated regex literal
      # recompiles (PCRE2 JIT) on every evaluation, i.e. twice per line
      # per JSON variable.
      var_patterns = json_var_names.map do |json_var_name|
        {json_var_name,
         /[^a-zA-Z_]#{json_var_name}\[[rf]?['"]([^'"]*)['"]\]/,
         /[^a-zA-Z_]#{json_var_name}\.get\([rf]?['"]([^'"]*)['"]/}
      end

      codeblock_lines.each do |codeblock_line|
        var_patterns.each do |json_var_name, subscript_regex, get_regex|
          next unless codeblock_line.includes?(json_var_name)
          matches = codeblock_line.scan(subscript_regex)
          if matches.size == 0
            matches = codeblock_line.scan(get_regex)
          end

          unless matches.nil?
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
        # A `def`/`class` signature frequently wraps across lines, with
        # the closing `)` and a `-> T:` return annotation sitting at
        # column 0 — at or below the body's indent. Those header lines
        # must not be mistaken for the block terminator, or the entire
        # body (and every callee in it) is dropped. Modern FastAPI
        # handlers (`def read_items(\n  session: Dep,\n) -> Any:`) hit
        # this on nearly every endpoint.
        header_span = python_signature_line_span(lines)
        lines[1..].each_with_index do |line, body_idx|
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
          # `body_idx` is 0-based within `lines[1..]`, so absolute line
          # `body_idx + 1`. While that is still inside the multi-line
          # signature, keep the line unconditionally.
          if body_idx + 1 < header_span
            end_index += line.size + 1
          elsif clear_line[0..(indent_size - 1)].strip.empty? || open_status
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

    # Number of physical lines a `def`/`class` signature occupies at the
    # head of `lines`, i.e. up to and including the line that carries the
    # suite-introducing `:` at bracket depth 0. A single-line header
    # returns 1. Used by `parse_code_block` to avoid treating a wrapped
    # signature's continuation lines (notably the `) -> T:` closer at
    # column 0) as the end of the body.
    def python_signature_line_span(lines : Array(::String)) : Int32
      depth = 0
      in_quote = nil
      escaped = false
      lines.each_with_index do |line, idx|
        line.each_char do |ch|
          if in_quote
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == in_quote
              in_quote = nil
            end
            next
          end
          case ch
          when '\'', '"'
            in_quote = ch
          when '(', '[', '{'
            depth += 1
          when ')', ']', '}'
            depth -= 1 if depth > 0
          when ':'
            return idx + 1 if depth == 0
          end
        end
      end
      1
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

    # Walk forward from `decorator_line` past any stacked decorators,
    # decorator continuation lines, blank lines, and comments to the
    # actual `def` / `async def` that they apply to. Returns the 0-based
    # line of the def, or nil if none is found before a non-decorator/
    # non-blank statement.
    #
    # This exists because real-world Python decorator stacks
    # (`@app.post(...)` + `@auth_required`, multi-line route decorators,
    # blank-line spacers, or a `# comment` between the route decorator
    # and the def) make the "def is at decorator_line + 1" assumption
    # silently wrong — both for parameter extraction and for handler-body
    # parsing.
    def find_def_line(lines : Array(::String), decorator_line : Int32) : Int32?
      i = decorator_line
      while i < lines.size
        stripped = lines[i].lstrip
        if stripped.starts_with?("def ") || stripped.starts_with?("async def ")
          return i
        end

        if stripped.starts_with?('@')
          paren_delta = python_paren_delta(lines[i])
          i += 1
          while i < lines.size && paren_delta > 0
            paren_delta += python_paren_delta(lines[i])
            i += 1
          end
          next
        end

        # Skip over blank lines and comment lines between decorators and
        # the handler. Django/FastAPI examples commonly use these as
        # visual separators in larger route modules.
        if stripped.empty? || stripped.starts_with?('#')
          i += 1
          next
        end

        # Anything else means we walked past the handler — give up.
        return
      end
      nil
    end

    # Build 1-hop callees observed in `body` (a handler's Python
    # source). `body_start_line` is the 0-based file line at which
    # `body`'s first character sits, so tree-sitter rows can be
    # translated into absolute call-site lines (1-indexed). Use when
    # one body maps to multiple endpoints (e.g. Sanic's multi-method
    # routes) so the tree-sitter parse happens once and the same
    # Callee list gets pushed onto each endpoint.
    #
    # Note: callers using `parse_code_block(lines[def_idx..])` should
    # pass `def_idx` because that helper keeps the def line. Callers
    # using `extract_function_body(lines, def_idx)` should pass
    # `def_idx + 1` because that helper skips the def line.
    # When `definition_base_path` is provided, callees with reachable
    # same-file or imported Python definitions are rewritten to that
    # definition location; unresolved callees keep their call-site
    # `path`/`line`.
    def build_callees_from(body : ::String,
                           body_start_line : Int32,
                           path : ::String,
                           *,
                           definition_base_path : ::String? = nil,
                           source : ::String? = nil) : Array(Callee)
      return [] of Callee unless callees_needed?
      return [] of Callee if body.empty?
      callees = Noir::PythonCalleeExtractor.calls_in(body).map do |entry|
        name, row = entry
        Callee.new(name, path: path, line: body_start_line + row + 1)
      end

      return callees unless base_path = definition_base_path

      resolve_python_callee_definitions(callees, base_path, path, source)
    end

    # Callees feed both `--include-callee` (direct output) and `--ai-context`
    # (aggregated review context). Skip the tree-sitter walk and import-graph
    # resolution when neither flag is set so default Python scans avoid the
    # per-handler callee build.
    private def callees_needed? : Bool
      any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
    end

    # Convenience wrapper around `build_callees_from`: parse + push in
    # one call when one body maps to exactly one endpoint.
    # `Endpoint#push_callee` enforces dedup and the per-endpoint cap.
    def push_callees_from(endpoint : Endpoint,
                          body : ::String,
                          body_start_line : Int32,
                          path : ::String,
                          *,
                          definition_base_path : ::String? = nil,
                          source : ::String? = nil) : Nil
      build_callees_from(
        body,
        body_start_line,
        path,
        definition_base_path: definition_base_path,
        source: source
      ).each { |c| endpoint.push_callee(c) }
    end

    private def resolve_python_callee_definitions(callees : Array(Callee),
                                                  app_base_path : ::String,
                                                  caller_path : ::String,
                                                  caller_source : ::String?) : Array(Callee)
      source_cache = Hash(::String, ::String).new
      source_cache[caller_path] = caller_source || read_file_content(caller_path)
      import_map = find_imported_modules(app_base_path, caller_path, source_cache[caller_path])

      callees.map do |callee|
        if definition = resolve_python_callee_definition(callee.name, caller_path, source_cache, import_map)
          definition_path, definition_line = definition
          Callee.new(callee.name, path: definition_path, line: definition_line)
        else
          callee
        end
      end
    rescue
      callees
    end

    private def resolve_python_callee_definition(name : ::String,
                                                 caller_path : ::String,
                                                 source_cache : Hash(::String, ::String),
                                                 import_map : Hash(::String, Tuple(::String, Int32))) : Tuple(::String, Int32)?
      parts = name.split(".")
      return if parts.empty?

      caller_source = source_cache[caller_path]
      if definition = find_python_definition(caller_path, caller_source, parts)
        return definition
      end

      first_part = parts[0]
      return unless imported = import_map[first_part]?

      imported_path = imported.first
      return if imported_path.empty? || !File.exists?(imported_path)

      imported_source = source_cache[imported_path] ||= read_file_content(imported_path)
      imported_parts = parts.size == 1 ? parts : parts[1..]
      find_python_definition(imported_path, imported_source, imported_parts) ||
        find_python_definition(imported_path, imported_source, parts)
    end

    private def find_python_definition(path : ::String, source : ::String, parts : Array(::String)) : Tuple(::String, Int32)?
      return if parts.empty?

      if parts.size == 1
        line = find_python_function_or_class_line(source, parts[0])
        return {path, line} if line
        return
      end

      if line = find_python_class_method_line(source, parts[0], parts[1])
        return {path, line}
      end
    end

    private def find_python_function_or_class_line(source : ::String, name : ::String) : Int32?
      source.lines.each_with_index do |line, index|
        stripped = line.lstrip
        next if stripped.starts_with?("#")
        if python_def_matches?(stripped, name) || python_class_matches?(stripped, name)
          return index + 1
        end
      end
    end

    private def find_python_class_method_line(source : ::String, class_name : ::String, method_name : ::String) : Int32?
      lines = source.lines
      class_indent : Int32? = nil

      lines.each_with_index do |line, index|
        stripped = line.lstrip
        next if stripped.starts_with?("#")

        if class_indent.nil?
          next unless python_class_matches?(stripped, class_name)

          class_indent = line.size - stripped.size
          next
        end

        indent = line.size - stripped.size
        next if stripped.empty? || stripped.starts_with?("@") || stripped.starts_with?("#")
        if current_class_indent = class_indent
          return if indent <= current_class_indent
        end

        return index + 1 if python_def_matches?(stripped, method_name)
      end
    end

    private def python_def_matches?(stripped : ::String, name : ::String) : Bool
      stripped.starts_with?("def #{name}(") || stripped.starts_with?("async def #{name}(")
    end

    private def python_class_matches?(stripped : ::String, name : ::String) : Bool
      stripped.starts_with?("class #{name}:") || stripped.starts_with?("class #{name}(")
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

    # Net `(` − `)` count on a single Python source line, ignoring
    # parens that fall inside single- or double-quoted strings on the
    # same line. Sufficient for decorator / function-call headers,
    # which never carry triple-quoted strings on the call line.
    #
    # Used by analyzers that walk source line-by-line and need to
    # join continuation lines into one logical call (e.g. multi-line
    # decorators in FastAPI / Litestar / Sanic / Bottle, multi-line
    # `Route(...)` entries in Starlette).
    def python_paren_delta(line : ::String) : Int32
      depth = 0
      in_quote = nil
      escaped = false
      line.each_char do |ch|
        if in_quote
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          next
        end
        case ch
        when '\'', '"'
          in_quote = ch
        when '('
          depth += 1
        when ')'
          depth -= 1
        end
      end
      depth
    end

    # Given a 0-based `index` into `lines` whose content `line` is
    # known to open a Python call whose `(` is unbalanced, join
    # continuation lines until the running paren delta drops to ≤ 0.
    # Returns the joined string with newlines collapsed to single
    # spaces so analyzer-side regexes don't need a multi-line flag.
    # The caller is expected to short-circuit (`return line`) when
    # the call already balances on the same line — this method
    # always walks forward at least once.
    def join_until_python_call_closes(lines : Array(::String),
                                      index : Int32,
                                      line : ::String) : ::String
      pieces = [line]
      delta = python_paren_delta(line)
      i = index + 1
      while i < lines.size && delta > 0
        nxt = lines[i]
        pieces << nxt
        delta += python_paren_delta(nxt)
        break if delta <= 0
        i += 1
      end
      pieces.join(' ')
    end
  end
end
