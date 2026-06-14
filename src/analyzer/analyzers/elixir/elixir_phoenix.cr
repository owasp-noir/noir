require "../../engines/elixir_engine"
require "../../../utils/url_path"

module Analyzer::Elixir
  class Phoenix < ElixirEngine
    alias ScopeEntry = NamedTuple(prefix: String, module_prefix: String, indent: Int32)
    # Route-map keys carry the configured base so multi-base (monorepo)
    # scans keep each service's controller/action mapping isolated.
    alias RouteMapKey = Tuple(String, String)

    # Store mapping of route -> controller/action for parameter extraction
    @route_map : Hash(RouteMapKey, ControllerAction) = Hash(RouteMapKey, ControllerAction).new
    @route_macros : Hash(String, RouteMacro) = Hash(String, RouteMacro).new

    # `get`/`post`/… → its precompiled route regex. `add_standard_route` runs
    # once per verb per line of every `.ex` file; `Regex.new` there recompiled
    # the same 7 PCRE2 patterns on every call (~3.4M recompiles on a 2400-file
    # repo, the dominant scan cost). The pattern depends only on the fixed verb
    # set, so build it once. See `add_standard_route` for the shape rationale.
    STANDARD_ROUTE_METHODS = {
      "get"     => "GET",
      "post"    => "POST",
      "patch"   => "PATCH",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "options" => "OPTIONS",
      "head"    => "HEAD",
    }
    STANDARD_ROUTE_PATTERNS = STANDARD_ROUTE_METHODS.keys.to_h do |verb|
      {verb, Regex.new("(?:^|[^.\\w])#{verb}\\s*(?:\\(\\s*)?['\"]([^'\"]+)['\"]\\s*,\\s*([A-Z]\\w*(?:\\.[A-Za-z_]\\w*)*|unquote\\(\\s*\\w+\\s*\\))(?=\\s*[,)]|\\s*$)(?:\\s*,\\s*:(\\w+[!?]?))?")}
    end

    struct ControllerAction
      property controller : String
      property action : String

      def initialize(@controller : String, @action : String)
      end
    end

    struct RouteMacro
      property name : String
      property module_name : String?
      property param_names : Array(String)
      property default_bindings : Hash(String, String)
      property body_lines : Array(String)

      def initialize(@name : String,
                     @module_name : String?,
                     @param_names : Array(String),
                     @default_bindings : Hash(String, String),
                     @body_lines : Array(String))
      end
    end

    struct RouteMacroInvocation
      property route_macro : RouteMacro
      property positional_args : Array(String)
      property keyword_args : Hash(String, String)

      def initialize(@route_macro : RouteMacro,
                     @positional_args : Array(String),
                     @keyword_args : Hash(String, String))
      end
    end

    def analyze
      collect_route_macros

      # First pass: collect routes via the engine's parallel file scan.
      super

      # Second pass: extract parameters from controller files
      extract_controller_params

      @result
    end

    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint unless File.extname(path) == ".ex"

      base = configured_base_for(path)
      endpoints = [] of Endpoint
      scope_stack = [] of ScopeEntry
      string_bindings = Hash(String, String).new
      in_triple_double = false
      in_triple_single = false

      content = File.open(path, "r", encoding: "utf-8", invalid: :skip, &.gets_to_end)
      lines = content.lines
      current_module = extract_module_name(content)

      index = 0
      while index < lines.size
        line = lines[index]

        if line.includes?("\"\"\"")
          line.scan(/"""/).size.times { in_triple_double = !in_triple_double }
          index += 1
          next
        end
        if line.includes?("'''")
          line.scan(/'''/).size.times { in_triple_single = !in_triple_single }
          index += 1
          next
        end
        if in_triple_double || in_triple_single
          index += 1
          next
        end

        stripped = line.strip
        if stripped.starts_with?("#")
          index += 1
          next
        end

        if stripped.starts_with?("defmacro ")
          macro_end = find_function_end(lines, index)
          index = macro_end == -1 ? index + 1 : macro_end + 1
          next
        end

        update_elixir_string_bindings(string_bindings, line)

        if !scope_stack.empty?
          if end_match = line.match(/^(\s*)end\b/)
            end_indent = end_match[1].size
            if end_indent == scope_stack.last[:indent]
              scope_stack.pop
              index += 1
              next
            end
          end
        end

        if match = line.match(/^(\s*)scope\s*(?:\(\s*)?["']([^"']+)["'](?:\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*))?/)
          scope_stack << {prefix: match[2], module_prefix: match[3]? || "", indent: match[1].size}
          index += 1
          next
        end

        if match = line.match(/^(\s*)scope\s*(?:\(\s*)?unquote\(\s*(\w+)\s*\)(?:\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*))?/)
          scope_stack << {prefix: string_bindings[match[2]]? || "", module_prefix: match[3]? || "", indent: match[1].size}
          index += 1
          next
        end

        scope_prefix = current_scope_prefix(scope_stack)
        scope_module = current_scope_module(scope_stack)

        if invocation = route_macro_invocation(line, current_module)
          expanded = endpoints_from_route_macro(invocation, path, index + 1, scope_prefix, scope_module)
          expanded.each do |endpoint|
            next if endpoint.method.empty?
            endpoints << endpoint
          end
          index += 1
          next
        end

        # The `resources` macro can span several lines (options such as
        # `only:`/`except:` are often wrapped onto continuation lines)
        # and can open a `do` block that nests child resources under a
        # `/:parent_id` member segment. Both need the whole logical
        # statement, so assemble it before extracting routes.
        if line.matches?(/(?:^|[^.\w])resources\s*(?:\(\s*)?["']/)
          statement, consumed = assemble_statement(lines, index)
          res_endpoints, nested_prefix = resources_from_statement(statement, scope_prefix, scope_module, base, string_bindings)
          res_endpoints.each do |endpoint|
            next if endpoint.method.empty?
            endpoint.details = Details.new(PathInfo.new(path, index + 1))
            endpoints << endpoint
          end
          if nested_prefix
            indent = line.size - line.lstrip.size
            scope_stack << {prefix: nested_prefix, module_prefix: "", indent: indent}
          end
          index += consumed
          next
        end

        line_to_endpoint(line, path, scope_prefix, scope_module, base, string_bindings).each do |endpoint|
          next if endpoint.method.empty?
          endpoint.details = Details.new(PathInfo.new(path, index + 1))
          endpoints << endpoint
        end
        index += 1
      end
      endpoints
    end

    # Join the line at `start` with any continuation lines so a route
    # macro split across several physical lines is parsed as one. A
    # statement is still "open" while its last meaningful character is a
    # comma or it has more open brackets than closing ones — the shape
    # Elixir uses to wrap keyword options. Returns the assembled
    # single-line statement and how many physical lines it consumed.
    private def assemble_statement(lines : Array(String), start : Int32) : Tuple(String, Int32)
      buffer = strip_trailing_comment(lines[start]).rstrip
      consumed = 1
      while statement_open?(buffer) && (start + consumed) < lines.size
        nxt = strip_trailing_comment(lines[start + consumed]).strip
        buffer = "#{buffer} #{nxt}".rstrip
        consumed += 1
        break if consumed > 12 # safety bound: route options never wrap this far
      end
      {buffer, consumed}
    end

    private def update_elixir_string_bindings(bindings : Hash(String, String), line : String) : Nil
      update_elixir_string_bindings(bindings, line, Hash(String, String).new)
    end

    private def update_elixir_string_bindings(bindings : Hash(String, String),
                                              line : String,
                                              keyword_overrides : Hash(String, String)) : Nil
      code = strip_trailing_comment(line).strip

      if match = code.match(/^(\w+)\s*=\s*Keyword\.get\([^,]+,\s*:\w+\s*,\s*["']([^"']+)["']\s*\)/)
        key = code.match(/Keyword\.get\([^,]+,\s*:(\w+)/).try(&.[1])
        bindings[match[1]] = key.try { |name| keyword_overrides[name]? } || match[2]
      elsif match = code.match(/^(\w+)\s*=\s*Keyword\.get\([^,]+,\s*:\w+\s*,\s*([A-Z]\w*(?:\.[A-Z]\w*)*)\s*\)/)
        key = code.match(/Keyword\.get\([^,]+,\s*:(\w+)/).try(&.[1])
        bindings[match[1]] = key.try { |name| keyword_overrides[name]? } || match[2]
      elsif match = code.match(/^(\w+)\s*=\s*["']([^"']+)["']/)
        bindings[match[1]] = match[2]
      end

      code.scan(/(\w+)\s*\\\\\s*([A-Z]\w*(?:\.[A-Z]\w*)*)/) do |default_match|
        bindings[default_match[1]] = default_match[2]
      end
    end

    private def statement_open?(buffer : String) : Bool
      # Judge continuation on a string-blanked copy so brackets/commas
      # inside a literal path (`resources "/a[b", Ctrl`) don't read as an
      # unbalanced, still-open statement.
      trimmed = Noir::ElixirCalleeExtractor.strip_comment(buffer).rstrip
      return false if trimmed.empty?
      return true if trimmed.ends_with?(",")
      opens = trimmed.count('[') + trimmed.count('(') + trimmed.count('{')
      closes = trimmed.count(']') + trimmed.count(')') + trimmed.count('}')
      opens > closes
    end

    # Drop an Elixir line comment while preserving the string literals
    # (and their quotes) the `resources` regex depends on — unlike the
    # callee extractor's `strip_comment`, which discards quotes. A `#`
    # only opens a comment outside a string, so a `#` inside a quoted
    # path won't truncate the statement.
    private def strip_trailing_comment(line : String) : String
      in_string = false
      escaped = false
      quote = '\0'
      line.each_char_with_index do |char, i|
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '"' || char == '\''
          in_string = true
          quote = char
        elsif char == '#'
          return line[0, i]
        end
      end
      line
    end

    def extract_controller_params
      # Find all controller files and extract parameters. Pulls from the
      # detector-built file_map so subtree pruning and --exclude-path
      # apply to this pass too.
      controller_files = get_files_by_extension(".ex").select do |path|
        next false unless path.ends_with?("_controller.ex")
        base_paths.any? { |base| path_under_root?(path, base) }
      end

      controller_files.each do |controller_path|
        next unless File.exists?(controller_path)

        begin
          content = read_file_content(controller_path)
          controller_name = File.basename(controller_path, ".ex")
          controller_module = extract_controller_module(content) || controller_name

          # Extract parameters from each action in the controller
          extract_params_from_controller(content, controller_module, controller_path)
        rescue e
          logger.debug "Error reading controller file #{controller_path}: #{e}"
        end
      end
    end

    def extract_params_from_controller(content : String, controller_name : String, controller_path : String)
      lines = content.lines
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      endpoints_by_action = endpoints_for_controller(controller_name, controller_path)

      index = 0
      while index < lines.size
        line = lines[index]

        if line.matches?(/^\s*defp\s/) || !(name_match = line.match(/^\s*def\s+(\w+)\(/))
          index += 1
          next
        end
        action_name = name_match[1]

        # A controller action's first argument is always the connection,
        # but the head can pattern-match it (`def edit(conn = %{assigns:
        # …}, _params)`, `def show(%Plug.Conn{} = conn, params)`) and a
        # long head can wrap the args across several lines
        # (`def update(\n  conn,\n  params\n) do`). Assemble the whole
        # head so the block body is located correctly, then confirm the
        # first argument really binds `conn` before treating it as an
        # action.
        signature, body_start = assemble_def_signature(lines, index)
        unless signature.matches?(/\(\s*(?:_?conn\b|%[^,)]*\bconn\b)/)
          index += 1
          next
        end

        matching_endpoints = endpoints_by_action[action_name]? || [] of Endpoint
        if matching_endpoints.empty?
          index += 1
          next
        end

        # Find the end of the function block once per controller action.
        block_end = find_function_end(lines, body_start)
        if block_end == -1
          index += 1
          next
        end

        callees = include_callee ? callees_from_function_block(lines, body_start, block_end, controller_path) : nil

        matching_endpoints.each do |endpoint|
          append_code_path(endpoint.details, PathInfo.new(controller_path, index + 1))

          # Extract parameters from the function block
          params = extract_params_from_function_block(lines, body_start, block_end, endpoint.method)
          params.each { |param| endpoint.push_param(param) }

          attach_elixir_callees(endpoint, callees) if callees
        end

        index += 1
      end
    end

    # Join a `def` head that may span several physical lines and return
    # `{assembled_head, body_start}` where `body_start` is the line that
    # opens the block (`) do` / `do`). Tracks parenthesis depth so the
    # arg list is closed before the block-opening `do` is recognised
    # (and the inline `do:` keyword form is ignored). Falls back to the
    # definition line itself if no block opener turns up within a small
    # bound.
    private def assemble_def_signature(lines : Array(String), start : Int32) : Tuple(String, Int32)
      buffer = ""
      paren = 0
      i = start
      limit = Math.min(lines.size, start + 16)
      while i < limit
        text = strip_trailing_comment(lines[i])
        buffer = buffer.empty? ? text.strip : "#{buffer} #{text.strip}"
        # Count parens and look for the block `do` on a string-blanked
        # copy so a paren or the word `do` inside a default value
        # (`def f(x \\ "(")`, `def f(mode \\ :do)`) doesn't skew the
        # depth or fire early.
        code = Noir::ElixirCalleeExtractor.strip_comment(text)
        paren += code.count('(') - code.count(')')
        # The block opens at the first top-level `do` once the argument
        # list's parentheses are balanced; the paren guard keeps a `do`
        # buried in a default value or atom inside the args from firing.
        if paren <= 0 && code.matches?(/\bdo\b(?!:)/)
          return {buffer, i}
        end
        i += 1
      end
      {buffer, start}
    end

    private def collect_route_macros : Nil
      @route_macros.clear

      get_files_by_extension(".ex").each do |path|
        next unless File.exists?(path)

        begin
          content = read_file_content(path)
          module_name = extract_module_name(content)
          lines = content.lines
          index = 0

          while index < lines.size
            line = lines[index]
            stripped = line.strip

            unless stripped.starts_with?("defmacro ")
              index += 1
              next
            end

            signature, body_start = assemble_def_signature(lines, index)
            name = signature.match(/\bdefmacro\s+(\w+[!?]?)/).try(&.[1])
            macro_end = find_function_end(lines, body_start)
            if name.nil? || macro_end == -1
              index += 1
              next
            end

            body_lines = lines[(body_start + 1)...macro_end] || [] of String
            default_bindings = Hash(String, String).new
            update_elixir_string_bindings(default_bindings, signature)
            body_lines.each { |body_line| update_elixir_string_bindings(default_bindings, body_line) }
            route_macro = RouteMacro.new(
              name,
              module_name,
              parse_macro_param_names(signature),
              default_bindings,
              body_lines
            )

            @route_macros[name] = route_macro
            @route_macros["#{module_name}.#{name}"] = route_macro if module_name

            index = macro_end + 1
          end
        rescue e
          logger.debug "Error collecting Phoenix route macros from #{path}: #{e}"
        end
      end
    end

    private def parse_macro_param_names(signature : String) : Array(String)
      params = [] of String
      args = signature.match(/\bdefmacro\s+\w+[!?]?\s*\((.*)\)\s+do\b/).try(&.[1])
      return params unless args

      split_top_level_commas(args).each do |part|
        if match = part.strip.match(/^(\w+)/)
          params << match[1]
        end
      end
      params
    end

    private def route_macro_invocation(line : String, current_module : String?) : RouteMacroInvocation?
      code = strip_trailing_comment(line).strip
      return if code.empty?

      if use_match = code.match(/^use\s+([A-Z]\w*(?:\.[A-Z]\w*)*)(?:\s*,\s*(.*))?$/)
        route_macro = @route_macros["#{use_match[1]}.__using__"]?
        return unless route_macro

        keyword_args = parse_keyword_args(use_match[2]? || "")
        return RouteMacroInvocation.new(route_macro, [] of String, keyword_args)
      end

      call_match = code.match(/^(?:(?<module>[A-Z]\w*(?:\.[A-Z]\w*)*)\.)?(?<name>[a-z_]\w*[!?]?)\s*(?:\((?<args>.*)\)|(?<bare>.*))?$/)
      return unless call_match

      name = call_match["name"]
      module_name = call_match["module"]?
      route_macro = if module_name
                      @route_macros["#{module_name}.#{name}"]?
                    elsif current_module && @route_macros.has_key?("#{current_module}.#{name}")
                      @route_macros["#{current_module}.#{name}"]
                    else
                      @route_macros[name]?
                    end
      return unless route_macro

      args_text = call_match["args"]? || call_match["bare"]? || ""
      positional_args, keyword_args = parse_macro_call_args(args_text)
      RouteMacroInvocation.new(route_macro, positional_args, keyword_args)
    end

    private def parse_macro_call_args(args_text : String) : Tuple(Array(String), Hash(String, String))
      positional_args = [] of String
      keyword_args = Hash(String, String).new

      split_top_level_commas(args_text).each do |part|
        stripped = part.strip
        next if stripped.empty?

        if match = stripped.match(/^(\w+):\s*(.+)$/)
          value = literal_macro_value(match[2])
          keyword_args[match[1]] = value if value
        elsif value = literal_macro_value(stripped)
          positional_args << value
        end
      end

      {positional_args, keyword_args}
    end

    private def parse_keyword_args(args_text : String) : Hash(String, String)
      _, keyword_args = parse_macro_call_args(args_text)
      keyword_args
    end

    private def literal_macro_value(value : String) : String?
      stripped = value.strip
      if match = stripped.match(/^["']([^"']+)["']$/)
        match[1]
      elsif stripped.matches?(/^[A-Z]\w*(?:\.[A-Z]\w*)*$/)
        stripped
      end
    end

    private def split_top_level_commas(text : String) : Array(String)
      parts = [] of String
      buffer = String::Builder.new
      depth = 0
      in_string = false
      escaped = false
      quote = '\0'

      text.each_char do |char|
        if in_string
          buffer << char
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
          buffer << char
        when '(', '[', '{'
          depth += 1
          buffer << char
        when ')', ']', '}'
          depth -= 1 if depth > 0
          buffer << char
        when ','
          if depth == 0
            parts << buffer.to_s
            buffer = String::Builder.new
          else
            buffer << char
          end
        else
          buffer << char
        end
      end

      parts << buffer.to_s
      parts
    end

    private def endpoints_from_route_macro(invocation : RouteMacroInvocation,
                                           path : String,
                                           call_line : Int32,
                                           outer_scope_prefix : String,
                                           outer_scope_module : String) : Array(Endpoint)
      route_macro = invocation.route_macro
      base = configured_base_for(path)
      bindings = route_macro.default_bindings.dup
      route_macro.param_names.each_with_index do |param_name, index|
        if value = invocation.positional_args[index]?
          bindings[param_name] = value
        end
      end

      scope_stack = [] of ScopeEntry
      endpoints = [] of Endpoint
      index = 0

      while index < route_macro.body_lines.size
        line = route_macro.body_lines[index]
        stripped = line.strip

        if stripped.starts_with?("#")
          index += 1
          next
        end

        update_elixir_string_bindings(bindings, line, invocation.keyword_args)

        if !scope_stack.empty?
          if end_match = line.match(/^(\s*)end\b/)
            end_indent = end_match[1].size
            if end_indent == scope_stack.last[:indent]
              scope_stack.pop
              index += 1
              next
            end
          end
        end

        if match = line.match(/^(\s*)scope\s*(?:\(\s*)?["']([^"']+)["'](?:\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*))?/)
          scope_stack << {prefix: match[2], module_prefix: match[3]? || "", indent: match[1].size}
          index += 1
          next
        end

        if match = line.match(/^(\s*)scope\s*(?:\(\s*)?unquote\(\s*(\w+)\s*\)(?:\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*))?/)
          unless prefix = bindings[match[2]]?
            index += 1
            next
          end
          scope_stack << {prefix: prefix, module_prefix: match[3]? || "", indent: match[1].size}
          index += 1
          next
        end

        scope_prefix = Noir::URLPath.join(outer_scope_prefix, current_scope_prefix(scope_stack))
        scope_module = combine_scope_modules(outer_scope_module, current_scope_module(scope_stack))

        if line.matches?(/(?:^|[^.\w])resources\s*(?:\(\s*)?["']/)
          statement, consumed = assemble_statement(route_macro.body_lines, index)
          res_endpoints, nested_prefix = resources_from_statement(statement, scope_prefix, scope_module, base, bindings)
          res_endpoints.each do |endpoint|
            endpoint.details = Details.new(PathInfo.new(path, call_line))
            endpoints << endpoint
          end
          if nested_prefix
            indent = line.size - line.lstrip.size
            scope_stack << {prefix: nested_prefix, module_prefix: "", indent: indent}
          end
          index += consumed
          next
        end

        line_to_endpoint(line, path, scope_prefix, scope_module, base, bindings).each do |endpoint|
          endpoint.details = Details.new(PathInfo.new(path, call_line))
          endpoints << endpoint
        end

        index += 1
      end

      endpoints
    end

    private def endpoints_for_controller(controller_name : String, controller_path : String) : Hash(String, Array(Endpoint))
      endpoints_by_action = Hash(String, Array(Endpoint)).new { |hash, key| hash[key] = [] of Endpoint }
      base = configured_base_for(controller_path)

      @result.each do |endpoint|
        route_key = endpoint_route_map_key(endpoint)
        # Keep param extraction scoped to the controller's own base so a
        # monorepo's sibling services don't borrow each other's params.
        next unless route_key[0] == base
        next unless mapping = @route_map[route_key]?
        next unless controller_refs_match?(controller_name, mapping.controller)

        endpoints_by_action[mapping.action] << endpoint
      end

      endpoints_by_action
    end

    # Route-map key for a recorded route: the configured base plus the
    # `METHOD::path` discriminator.
    private def route_map_key(base : String, method : String, path : String) : RouteMapKey
      {base, "#{method}::#{path}"}
    end

    # Route-map key for an already-emitted endpoint, deriving its base from
    # the route file the endpoint was discovered in.
    private def endpoint_route_map_key(endpoint : Endpoint) : RouteMapKey
      route_path = endpoint.details.code_paths.first?
      base = route_path ? configured_base_for(route_path.path) : @base_path
      {base, "#{endpoint.method}::#{endpoint.url}"}
    end

    def should_extract_params_for_endpoint?(endpoint : Endpoint, controller_name : String, action_name : String) : Bool
      # Check if the endpoint's route_map entry matches this controller/action
      route_key = endpoint_route_map_key(endpoint)
      if mapping = @route_map[route_key]?
        return controller_refs_match?(controller_name, mapping.controller) && mapping.action == action_name
      end

      # Fallback: try to match by conventional naming
      # For example, resources routes: GET /posts -> PostController.index
      false
    end

    private def controller_refs_match?(controller_name : String, mapped_controller : String) : Bool
      normalized_controller = normalize_controller_ref(controller_name)
      normalized_mapping = normalize_controller_ref(mapped_controller)
      if mapped_controller.includes?(".")
        normalized_controller == normalized_mapping
      else
        normalized_controller.split('.').last == normalized_mapping
      end
    end

    def find_function_end(lines : Array(String), start_index : Int32) : Int32
      # Find the matching "end" for the function starting with "def"
      return -1 if start_index >= lines.size

      depth = 1
      (start_index + 1...lines.size).each do |i|
        depth += elixir_block_depth_delta(lines[i].strip)
        return i if depth == 0
      end

      -1
    end

    def extract_params_from_function_block(lines : Array(String), start_index : Int32, end_index : Int32, method : String) : Array(Param)
      params = Array(Param).new
      seen_params = Set(String).new # Track seen params for O(1) lookup

      # Extract parameters from the function block content
      (start_index..end_index).each do |i|
        line = lines[i]

        # Extract query parameters (conn.query_params["param"])
        line.scan(/conn\.query_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "query:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "query")
            seen_params << param_key
          end
        end

        # Extract params (could be query for GET or form for POST/PUT/PATCH)
        line.scan(/conn\.params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_type = (method == "GET") ? "query" : "form"
          param_key = "#{param_type}:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", param_type)
            seen_params << param_key
          end
        end

        # Extract body parameters (conn.body_params["param"])
        line.scan(/conn\.body_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "form:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "form")
            seen_params << param_key
          end
        end

        # Extract header parameters (get_req_header(conn, "header-name"))
        line.scan(/get_req_header\(conn,\s*["']([^"']+)["']\)/) do |match|
          param_name = match[1]
          param_key = "header:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "header")
            seen_params << param_key
          end
        end

        # Extract cookie parameters (conn.cookies["cookie_name"])
        line.scan(/conn\.cookies\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "cookie:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "cookie")
            seen_params << param_key
          end
        end
      end

      params
    end

    private def append_code_path(details : Details, path_info : PathInfo)
      return if details.code_paths.any? { |existing| existing == path_info }
      details.add_path(path_info)
    end

    private def callees_from_function_block(lines : Array(String),
                                            start_index : Int32,
                                            end_index : Int32,
                                            controller_path : String) : Array(Noir::ElixirCalleeExtractor::Entry)
      return [] of Noir::ElixirCalleeExtractor::Entry if end_index <= start_index

      body_lines = lines[(start_index + 1)...end_index]
      return [] of Noir::ElixirCalleeExtractor::Entry if body_lines.empty?

      Noir::ElixirCalleeExtractor.callees_for_lines(body_lines, controller_path, start_index + 2)
    end

    private def extract_controller_module(content : String) : String?
      extract_module_name(content)
    end

    private def extract_module_name(content : String) : String?
      content.each_line do |line|
        if match = line.match(/^\s*defmodule\s+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+do\b/)
          return match[1]
        end
      end
    end

    private def normalize_controller_ref(controller : String) : String
      normalized = controller.downcase.gsub("_controller", "controller")
      normalized.ends_with?("controller") ? normalized[0, normalized.size - "controller".size] : normalized
    end

    private def current_scope_prefix(scope_stack : Array(ScopeEntry)) : String
      prefix = ""
      scope_stack.each do |scope|
        prefix = Noir::URLPath.join(prefix, scope[:prefix])
      end
      prefix
    end

    private def current_scope_module(scope_stack : Array(ScopeEntry)) : String
      scope_module = ""
      scope_stack.each do |scope|
        module_prefix = scope[:module_prefix]
        next if module_prefix.empty?

        if scope_module.empty? || module_prefix.starts_with?("#{scope_module}.")
          scope_module = module_prefix
        else
          scope_module = "#{scope_module}.#{module_prefix}"
        end
      end
      scope_module
    end

    private def combine_scope_modules(left : String, right : String) : String
      return right if left.empty?
      return left if right.empty?
      return right if right.starts_with?("#{left}.")
      "#{left}.#{right}"
    end

    private def scoped_route_path(scope_prefix : String, route_path : String) : String
      Noir::URLPath.join(
        normalize_elixir_interpolation(scope_prefix),
        normalize_elixir_interpolation(route_path),
      )
    end

    # Elixir double-quoted strings interpolate `#{expr}`, and the
    # Phoenix Router DSL captures the literal characters between
    # quotes. Without normalization, `get "/api/#{@version}/items"`
    # produced URL `/api/#{@version}/items` with the `#{@…}` syntax
    # leaking into the path. Rewrite each interpolation site to a
    # `{name}` placeholder (stripping any leading `@` module-
    # attribute sigil) so the path-parameter extractor recognises
    # it and the URL template reads cleanly. Mirrors the Python
    # f-string, Ruby `#{}`, PHP `$var`, and Crystal `#{}` fixes.
    private def normalize_elixir_interpolation(path : String) : String
      path.gsub(/\#\{([^}]+)\}/) do |_|
        token = $~[1].strip.lstrip('@')
        "{#{token}}"
      end
    end

    private def scoped_controller(scope_module : String, controller : String) : String
      return controller if scope_module.empty?
      return controller if controller.starts_with?("#{scope_module}.")
      "#{scope_module}.#{controller}"
    end

    private def resolve_unquoted_ref(ref : String, bindings : Hash(String, String)) : String?
      if match = ref.match(/^unquote\(\s*(\w+)\s*\)$/)
        bindings[match[1]]?
      else
        ref
      end
    end

    def line_to_endpoint(line : String,
                         file_path : String,
                         scope_prefix : String = "",
                         scope_module : String = "",
                         base : String = @base_path,
                         string_bindings : Hash(String, String) = Hash(String, String).new) : Array(Endpoint)
      endpoints = Array(Endpoint).new

      # Standard HTTP methods - extract controller and action info
      add_standard_route(endpoints, line, "get", "GET", scope_prefix, scope_module, base, string_bindings)
      add_standard_route(endpoints, line, "post", "POST", scope_prefix, scope_module, base, string_bindings)
      add_standard_route(endpoints, line, "patch", "PATCH", scope_prefix, scope_module, base, string_bindings)
      add_standard_route(endpoints, line, "put", "PUT", scope_prefix, scope_module, base, string_bindings)
      add_standard_route(endpoints, line, "delete", "DELETE", scope_prefix, scope_module, base, string_bindings)
      add_standard_route(endpoints, line, "options", "OPTIONS", scope_prefix, scope_module, base, string_bindings)
      add_standard_route(endpoints, line, "head", "HEAD", scope_prefix, scope_module, base, string_bindings)

      # Socket routes
      line.scan(/(?:^|[^.\w])socket\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
        tmp = Endpoint.new(scoped_route_path(scope_prefix, match[1]), "GET")
        tmp.protocol = "ws"
        endpoints << tmp
      end

      # LiveView routes
      line.scan(/(?:^|[^.\w])live\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
        endpoints << Endpoint.new(scoped_route_path(scope_prefix, match[1]), "GET")
      end

      # Phoenix.LiveDashboard and forwarded plugs expose mounted HTTP surfaces.
      line.scan(/(?:^|[^.\w])live_dashboard\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        endpoints << Endpoint.new(scoped_route_path(scope_prefix, match[1]), "GET")
      end

      line.scan(/(?:^|[^.\w])forward\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        endpoints << Endpoint.new(scoped_route_path(scope_prefix, match[1]), "FORWARD")
      end

      if via_match = line.match(/(?:^|[^.\w])match\s*(?:\(\s*)?['"]([^'"]+)['"]\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*,\s*:(\w+[!?]?)[^\]]*via:\s*\[([^\]]+)\]/)
        path = scoped_route_path(scope_prefix, via_match[1])
        controller = scoped_controller(scope_module, via_match[2])
        controller_action = via_match[3]
        via_match[4].scan(/:(\w+)/) do |method_match|
          http_method = method_match[1].upcase
          @route_map[route_map_key(base, http_method, path)] = ControllerAction.new(controller, controller_action)
          endpoints << Endpoint.new(path, http_method)
        end
      end

      if match = line.match(/(?:^|[^.\w])match\s*(?:\(\s*)?:(\w+|\*)\s*,\s*['"]([^'"]+)['"]\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|unquote\(\s*\w+\s*\))\s*,\s*:(\w+[!?]?)/)
        http_methods = match_route_methods(match[1])
        path = scoped_route_path(scope_prefix, match[2])
        controller_action = match[4]
        controller = resolve_unquoted_ref(match[3], string_bindings)
        http_methods.each do |http_method|
          @route_map[route_map_key(base, http_method, path)] = ControllerAction.new(scoped_controller(scope_module, controller), controller_action) if controller
          endpoints << Endpoint.new(path, http_method)
        end
      end

      endpoints
    end

    # Expand a (possibly multi-line) `resources` macro into the REST
    # routes it generates. Returns the endpoints plus, when the macro
    # opens a `do` block, the relative member prefix (`path/:singular_id`)
    # that child routes nest under — `nil` for a leaf resource.
    private def resources_from_statement(statement : String,
                                         scope_prefix : String,
                                         scope_module : String,
                                         base : String,
                                         string_bindings : Hash(String, String)) : Tuple(Array(Endpoint), String?)
      endpoints = Array(Endpoint).new

      match = statement.match(/(?:^|[^.\w])resources\s*(?:\(\s*)?['"]([^'"]+)['"]\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*|unquote\(\s*\w+\s*\))/)
      return {endpoints, nil} unless match

      resource_path = match[1]
      base_path = scoped_route_path(scope_prefix, resource_path)
      controller = resolve_unquoted_ref(match[2], string_bindings)
      # `only:`/`except:` may sit behind other options (`as:`, `param:`,
      # `name:`), so scan the whole statement rather than anchoring them
      # to the controller argument.
      only_actions = statement.match(/\bonly:\s*\[([^\]]+)\]/).try &.[1]
      except_actions = statement.match(/\bexcept:\s*\[([^\]]+)\]/).try &.[1]

      # A `singleton: true` resource (e.g. a `/session` you always act on
      # without an id) drops the `/:id` member segment and omits `:index`
      # from the default action set. A `param:` option renames the member
      # capture (`param: "tenant_id"` → `/tenants/:tenant_id`).
      singleton = statement.matches?(/\bsingleton:\s*true\b/)
      param_name = statement.match(/\bparam:\s*["']?(\w+)["']?/).try(&.[1]) || "id"
      member = singleton ? base_path : "#{base_path}/:#{param_name}"

      if only_actions
        actions = only_actions.scan(/:(\w+)/).map { |m| m[1] }
      elsif singleton
        actions = ["show", "create", "update", "delete", "new", "edit"]
      else
        actions = ["index", "show", "create", "update", "delete", "new", "edit"]
      end
      if except_actions
        excluded = except_actions.scan(/:(\w+)/).map { |m| m[1] }
        actions = actions.reject { |action| excluded.includes?(action) }
      end

      actions.each do |action|
        case action
        when "index"
          @route_map[route_map_key(base, "GET", base_path)] = ControllerAction.new(scoped_controller(scope_module, controller), "index") if controller
          endpoints << Endpoint.new(base_path, "GET")
        when "show"
          @route_map[route_map_key(base, "GET", member)] = ControllerAction.new(scoped_controller(scope_module, controller), "show") if controller
          endpoints << Endpoint.new(member, "GET")
        when "create"
          @route_map[route_map_key(base, "POST", base_path)] = ControllerAction.new(scoped_controller(scope_module, controller), "create") if controller
          endpoints << Endpoint.new(base_path, "POST")
        when "update"
          @route_map[route_map_key(base, "PUT", member)] = ControllerAction.new(scoped_controller(scope_module, controller), "update") if controller
          endpoints << Endpoint.new(member, "PUT")
          @route_map[route_map_key(base, "PATCH", member)] = ControllerAction.new(scoped_controller(scope_module, controller), "update") if controller
          endpoints << Endpoint.new(member, "PATCH")
        when "delete"
          @route_map[route_map_key(base, "DELETE", member)] = ControllerAction.new(scoped_controller(scope_module, controller), "delete") if controller
          endpoints << Endpoint.new(member, "DELETE")
        when "new"
          @route_map[route_map_key(base, "GET", "#{base_path}/new")] = ControllerAction.new(scoped_controller(scope_module, controller), "new") if controller
          endpoints << Endpoint.new("#{base_path}/new", "GET")
        when "edit"
          @route_map[route_map_key(base, "GET", "#{member}/edit")] = ControllerAction.new(scoped_controller(scope_module, controller), "edit") if controller
          endpoints << Endpoint.new("#{member}/edit", "GET")
        end
      end

      nested_prefix = nil
      if statement.matches?(/\bdo\s*$/)
        if singleton
          nested_prefix = resource_path
        else
          # The child collection nests under the parent's member
          # capture: the explicit `param:` when given, otherwise the
          # singularized collection name (`/posts` → `:post_id`).
          nested_param = param_name == "id" ? "#{singularize(resource_path.split('/').reject(&.empty?).last? || resource_path)}_id" : param_name
          nested_prefix = Noir::URLPath.join(resource_path, ":#{nested_param}")
        end
      end

      {endpoints, nested_prefix}
    end

    # Phoenix names a nested resource's parent capture after the
    # singularized parent collection (`/posts/:post_id/...`). A small
    # English inflection covers the common cases; an imperfect singular
    # only affects the placeholder name, never the route structure.
    private def singularize(name : String) : String
      return "#{name[0, name.size - 3]}y" if name.ends_with?("ies") && name.size > 3
      return name[0, name.size - 1] if name.ends_with?("s") && name.size > 1
      name
    end

    private def add_standard_route(endpoints : Array(Endpoint),
                                   line : String,
                                   route_macro : String,
                                   http_method : String,
                                   scope_prefix : String,
                                   scope_module : String,
                                   base : String,
                                   string_bindings : Hash(String, String))
      # The `:action` atom is OPTIONAL: Phoenix's `get(path, plug, plug_opts
      # \\ [], opts \\ [])` lets a plug-style route omit it
      # (`get("/metrics", TelemetryUI.Web, [])`,
      # `get("/", WebAppController, [])`). Requiring `, :action` dropped every
      # such route (accent: 9 of ~48 missed). Capture the action when present
      # for the controller/action param map, but emit the endpoint regardless.
      #
      # Once the action is optional the 2nd arg MUST be a real controller
      # module — a capitalized name or `unquote(var)` that is NOT itself a
      # function call. Otherwise HTTP-CLIENT wrappers (common in Elixir) slip
      # through: `post("/api/v1/org/secrets", params, team)` (lowercase var,
      # already excluded by `[A-Z]`) and `post("com.atproto...",
      # Jason.encode!(params), [...])` (a `Module.fn(...)` call). The
      # `(?=\\s*[,)]|\\s*$)` lookahead requires the module reference to be
      # followed by an arg separator / call close — a `(` or `!` (a call)
      # rejects it.
      #
      # Cheap substring gate first: the precompiled regex still has to scan
      # the line, so skip it entirely for the (vast) majority of lines that
      # don't even contain the verb keyword.
      return unless line.includes?(route_macro)
      pattern = STANDARD_ROUTE_PATTERNS[route_macro]
      line.scan(pattern) do |match|
        full_path = scoped_route_path(scope_prefix, match[1])
        endpoint = Endpoint.new(full_path, http_method)
        if (controller = resolve_unquoted_ref(match[2], string_bindings)) && (action = match[3]?)
          @route_map[route_map_key(base, http_method, full_path)] = ControllerAction.new(scoped_controller(scope_module, controller), action)
        end
        endpoints << endpoint
      end
    end

    private def match_route_methods(method : String) : Array(String)
      return ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"] if method == "*"
      [method.upcase]
    end
  end
end
