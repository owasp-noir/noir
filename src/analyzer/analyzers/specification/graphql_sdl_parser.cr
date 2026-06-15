require "../../../models/endpoint"

module Analyzer::Specification
  # Shared GraphQL SDL parser. Extracted from `GraphqlSdl` so other
  # analyzers (Apollo Server's inline `gql\`...\`` typeDefs, Yoga, etc.)
  # can produce the same field-per-endpoint shape without re-implementing
  # the SDL grammar.
  module GraphqlSdlParser
    extend self

    DEFAULT_GRAPHQL_PATH = "/graphql"

    # Root operation type → GraphQL operation keyword.
    # All operations ride on POST (Noir's URL optimizer dedupes on method+url and
    # the HTTP method allowlist doesn't include WS); subscriptions are flagged
    # via `endpoint.protocol = "ws"` and a tag instead.
    ROOT_OPERATIONS = {
      "Query"        => "query",
      "Mutation"     => "mutation",
      "Subscription" => "subscription",
    }

    private struct InputField
      getter name : String
      getter type : String

      def initialize(@name, @type)
      end
    end

    # Parse an SDL document and return one endpoint per Query/Mutation/Subscription
    # field. `line_offset` shifts every reported line number — used by host
    # analyzers (e.g. Apollo Server) whose SDL is embedded in a larger file.
    def parse(content : String, file_path : String,
              default_path : String = DEFAULT_GRAPHQL_PATH,
              tag_source : String = "graphql_sdl_analyzer",
              line_offset : Int32 = 0) : Array(Endpoint)
      endpoints = [] of Endpoint
      sanitized = strip_comments(content)
      root_names = parse_schema_block(sanitized)
      input_types = parse_input_object_types(sanitized)
      visit_type_blocks(sanitized, file_path, root_names, default_path, tag_source,
        line_offset, input_types, endpoints)
      endpoints
    end

    # Returns the mapping of root operation type → root name (custom or default).
    private def parse_schema_block(content : String) : Hash(String, String)
      mapping = {"Query" => "Query", "Mutation" => "Mutation", "Subscription" => "Subscription"}

      if match = content.match(/\bschema\b\s*(?:@[\w]+(?:\([^)]*\))?\s*)*\{/m)
        brace_pos = content.index('{', match.begin(0) || 0)
        return mapping if brace_pos.nil?
        body = extract_brace_block(content, brace_pos)
        return mapping if body.nil?

        body.scan(/\b(query|mutation|subscription)\s*:\s*([A-Za-z_][A-Za-z0-9_]*)/) do |m|
          op = m[1].downcase
          name = m[2]
          case op
          when "query"        then mapping["Query"] = name
          when "mutation"     then mapping["Mutation"] = name
          when "subscription" then mapping["Subscription"] = name
          end
        end
      end

      mapping
    end

    private def visit_type_blocks(sanitized : String, file_path : String,
                                  root_names : Hash(String, String),
                                  default_path : String, tag_source : String,
                                  line_offset : Int32,
                                  input_types : Hash(String, Array(InputField)),
                                  endpoints : Array(Endpoint))
      root_alternation = root_names.values.uniq!.map { |n| Regex.escape(n) }.join("|")
      pattern = Regex.new("\\b(?:extend\\s+)?type\\s+(#{root_alternation})\\b(?:\\s+implements\\s+[^{]+)?\\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\\([^)]*\\))?\\s*)*\\{")

      sanitized.scan(pattern) do |match|
        type_name = match[1]
        root_op_name = root_names.find { |_, custom| custom == type_name }
        next if root_op_name.nil?
        root_kind = root_op_name[0]

        start_pos = match.begin(0) || 0
        brace_pos = sanitized.index('{', start_pos)
        next if brace_pos.nil?
        body = extract_brace_block(sanitized, brace_pos)
        next if body.nil?

        body_start_in_sanitized = brace_pos + 1
        parse_fields(body, body_start_in_sanitized, sanitized, file_path, root_kind,
          type_name, default_path, tag_source, line_offset, input_types, endpoints)
      end
    end

    private def parse_fields(body : String, body_offset : Int32, sanitized : String,
                             file_path : String, root_kind : String, type_name : String,
                             default_path : String, tag_source : String,
                             line_offset : Int32,
                             input_types : Hash(String, Array(InputField)),
                             endpoints : Array(Endpoint))
      operation_keyword = ROOT_OPERATIONS[root_kind]

      pos = 0
      while pos < body.size
        pos = skip_field_padding(body, pos)
        break if pos >= body.size

        field_match = body.match(/\G([A-Za-z_][A-Za-z0-9_]*)/, pos)
        break if field_match.nil?
        field_name = field_match[1]
        field_line = line_number_at(sanitized, body_offset + pos)
        field_line = field_line.try { |ln| ln + line_offset }
        cursor = pos + field_match[0].size

        cursor = skip_ws(body, cursor)
        args = [] of NamedTuple(name: String, type: String)
        if cursor < body.size && body[cursor] == '('
          args_block = extract_paren_block(body, cursor)
          close = matching_close_index(body, cursor, '(', ')')
          if args_block && close
            args = parse_arguments(args_block)
            # Jump past the *matching* close paren, not the first ')': an
            # argument's directive (`@length(min: 1)`, `@deprecated(...)`)
            # carries its own parentheses, and stopping at the first ')'
            # left the cursor mid-arguments — dropping the field and
            # misreading later argument names as fields.
            cursor = close + 1
          else
            cursor = advance_to_next_field(body, cursor)
            pos = cursor
            next
          end
        end

        cursor = skip_ws(body, cursor)
        if cursor >= body.size || body[cursor] != ':'
          pos = advance_to_next_field(body, cursor)
          next
        end
        cursor += 1
        cursor = skip_ws(body, cursor)

        return_type, after_type = read_type_reference(body, cursor)
        cursor = after_type
        directives, after_directives = read_directives(body, cursor)
        cursor = after_directives
        pos = advance_to_next_field(body, cursor)

        emit_endpoint(file_path, field_line, field_name, args, return_type, directives,
          operation_keyword, type_name, root_kind, default_path, tag_source, input_types, endpoints)
      end
    end

    private def emit_endpoint(file_path : String, line : Int32?, field_name : String,
                              args : Array(NamedTuple(name: String, type: String)),
                              return_type : String,
                              directives : Array(NamedTuple(name: String, args: String)),
                              operation_keyword : String,
                              type_name : String, root_kind : String,
                              default_path : String, tag_source : String,
                              input_types : Hash(String, Array(InputField)),
                              endpoints : Array(Endpoint))
      details = Details.new(PathInfo.new(file_path, line))
      params = [] of Param

      args.each do |arg|
        if fields = input_types[graphql_base_type_name(arg[:type])]?
          fields.each do |field|
            add_input_field_params(params, arg[:name], field, input_types, tag_source)
          end
        else
          push_param_once(params, Param.new(arg[:name], "", "json"))
        end
      end

      doc_param_name = "graphql_#{operation_keyword}_#{field_name}"
      doc_value = build_operation_document(operation_keyword, field_name, args, return_type)
      push_param_once(params, Param.new(doc_param_name, doc_value, "json"))

      url = "#{default_path}##{root_kind}.#{field_name}"
      endpoint = Endpoint.new(url, "POST", params, details)
      endpoint.protocol = "ws" if root_kind == "Subscription"

      endpoint.add_tag(Tag.new("graphql", "#{root_kind}.#{field_name}", tag_source))
      endpoint.add_tag(Tag.new("graphql-root", type_name, tag_source)) if type_name != root_kind
      endpoint.add_tag(Tag.new("graphql-return", return_type, tag_source)) unless return_type.empty?

      directives.each do |dir|
        endpoint.add_tag(Tag.new("graphql-directive", "@#{dir[:name]}#{dir[:args]}", tag_source))
      end

      endpoints << endpoint
    end

    private def parse_input_object_types(sanitized : String) : Hash(String, Array(InputField))
      input_types = Hash(String, Array(InputField)).new
      pattern = /\binput\s+([A-Za-z_][A-Za-z0-9_]*)\b\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*)*\{/

      sanitized.scan(pattern) do |match|
        type_name = match[1]
        start_pos = match.begin(0) || 0
        brace_pos = sanitized.index('{', start_pos)
        next if brace_pos.nil?
        body = extract_brace_block(sanitized, brace_pos)
        next if body.nil?

        input_types[type_name] = parse_input_fields(body)
      end

      input_types
    end

    private def parse_input_fields(body : String) : Array(InputField)
      fields = [] of InputField
      body.each_line do |line|
        line.scan(/([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([\[A-Za-z_][!\[\]A-Za-z0-9_]*)/) do |match|
          type_str = match[2].strip
          type_str = type_str.split(/\s+@|\s+=/).first.strip
          fields << InputField.new(match[1], type_str) unless type_str.empty?
        end
      end
      fields
    end

    private def add_input_field_params(params : Array(Param),
                                       argument_name : String,
                                       field : InputField,
                                       input_types : Hash(String, Array(InputField)),
                                       tag_source : String,
                                       prefix : String = "",
                                       depth : Int32 = 0)
      field_name = prefix.empty? ? graphql_input_param_name(argument_name, field.name) : "#{prefix}.#{field.name}"
      if depth < 2 && (nested_fields = input_types[graphql_base_type_name(field.type)]?)
        nested_fields.each do |nested_field|
          add_input_field_params(params, argument_name, nested_field, input_types, tag_source, field_name, depth + 1)
        end
        return
      end

      param = Param.new(field_name, "", "json")
      param.add_tag(Tag.new("graphql-input-field", argument_name, tag_source))
      push_param_once(params, param)
    end

    private def graphql_input_param_name(argument_name : String, field_name : String) : String
      argument_name == "input" ? field_name : "#{argument_name}.#{field_name}"
    end

    private def graphql_base_type_name(raw_type : String) : String
      raw_type.gsub(/[^A-Za-z0-9_]/, "")
    end

    private def push_param_once(params : Array(Param), param : Param)
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    private def build_operation_document(operation_keyword : String, field_name : String,
                                         args : Array(NamedTuple(name: String, type: String)),
                                         return_type : String) : String
      if args.empty?
        "#{operation_keyword} { #{field_name} }"
      else
        var_decls = args.map { |a| "$#{a[:name]}: #{a[:type]}" }.join(", ")
        call_args = args.map { |a| "#{a[:name]}: $#{a[:name]}" }.join(", ")
        "#{operation_keyword}(#{var_decls}) { #{field_name}(#{call_args}) }"
      end
    end

    # ---------- low-level parsers ----------

    # Replaces every comment and string literal with position-preserving
    # whitespace so the downstream grammar never has to reason about them.
    #
    # The input is first materialized into an `Array(Char)` so positional
    # access is O(1). Indexing a `String` directly (`content[i]`) is O(n)
    # whenever the document is not single-byte-optimizable — a single
    # multi-byte char (e.g. an emoji in a `"""description"""`) turns the
    # whole scan quadratic, which on real schemas like GitHub's 360 KB SDL
    # meant ~100 s instead of ~20 ms. The returned string is ASCII-only
    # (any stray non-ASCII char — which GraphQL only ever permits inside
    # strings/comments anyway — is mapped to a space), so every subsequent
    # positional pass over `sanitized` stays single-byte-optimizable too.
    private def strip_comments(content : String) : String
      chars = content.chars
      size = chars.size
      String.build(content.bytesize) do |io|
        i = 0
        while i < size
          ch = chars[i]
          case ch
          when '#'
            while i < size && chars[i] != '\n'
              io << ' '
              i += 1
            end
          when '"'
            if i + 2 < size && chars[i + 1] == '"' && chars[i + 2] == '"'
              io << "   "
              i += 3
              while i + 2 < size && !(chars[i] == '"' && chars[i + 1] == '"' && chars[i + 2] == '"')
                io << (chars[i] == '\n' ? '\n' : ' ')
                i += 1
              end
              if i + 2 < size
                io << "   "
                i += 3
              end
            else
              io << ' '
              i += 1
              while i < size && chars[i] != '"'
                if chars[i] == '\\' && i + 1 < size
                  io << "  "
                  i += 2
                else
                  io << (chars[i] == '\n' ? '\n' : ' ')
                  i += 1
                end
              end
              if i < size
                io << ' '
                i += 1
              end
            end
          else
            io << (ch.ascii? ? ch : ' ')
            i += 1
          end
        end
      end
    end

    private def extract_brace_block(content : String, open_pos : Int32) : String?
      extract_paired_block(content, open_pos, '{', '}')
    end

    private def extract_paren_block(content : String, open_pos : Int32) : String?
      extract_paired_block(content, open_pos, '(', ')')
    end

    private def extract_paired_block(content : String, open_pos : Int32,
                                     open_ch : Char, close_ch : Char) : String?
      depth = 0
      pos = open_pos
      while pos < content.size
        ch = content[pos]
        case ch
        when open_ch
          depth += 1
        when close_ch
          depth -= 1
          if depth == 0
            return content[(open_pos + 1)..(pos - 1)]
          end
        end
        pos += 1
      end
      nil
    end

    # Index of the close char that matches the opener at `open_pos` (nested
    # pairs counted), or nil when unbalanced. Unlike `String#index(close_ch)`
    # it skips over inner pairs — needed so a field/directive argument list
    # is not cut short at the first `)` belonging to a nested directive.
    private def matching_close_index(content : String, open_pos : Int32,
                                     open_ch : Char, close_ch : Char) : Int32?
      depth = 0
      pos = open_pos
      while pos < content.size
        ch = content[pos]
        if ch == open_ch
          depth += 1
        elsif ch == close_ch
          depth -= 1
          return pos if depth == 0
        end
        pos += 1
      end
      nil
    end

    private def skip_ws(content : String, pos : Int32) : Int32
      while pos < content.size && content[pos].ascii_whitespace?
        pos += 1
      end
      pos
    end

    private def skip_field_padding(content : String, pos : Int32) : Int32
      while pos < content.size && (content[pos].ascii_whitespace? || content[pos] == ',')
        pos += 1
      end
      pos
    end

    private def advance_to_next_field(content : String, pos : Int32) : Int32
      while pos < content.size && content[pos] != '\n' && content[pos] != ','
        pos += 1
      end
      pos += 1 if pos < content.size
      pos
    end

    private def parse_arguments(block : String) : Array(NamedTuple(name: String, type: String))
      args = [] of NamedTuple(name: String, type: String)
      pos = 0
      while pos < block.size
        pos = skip_field_padding(block, pos)
        break if pos >= block.size

        name_match = block.match(/\G([A-Za-z_][A-Za-z0-9_]*)/, pos)
        break if name_match.nil?
        name = name_match[1]
        cursor = pos + name_match[0].size

        cursor = skip_ws(block, cursor)
        if cursor >= block.size || block[cursor] != ':'
          pos = advance_past_arg(block, cursor)
          next
        end
        cursor += 1
        cursor = skip_ws(block, cursor)

        type_str, after_type = read_type_reference(block, cursor)
        cursor = after_type

        cursor = skip_ws(block, cursor)
        if cursor < block.size && block[cursor] == '='
          cursor = skip_default_value(block, cursor + 1)
        end

        _, after_directives = read_directives(block, cursor)
        cursor = after_directives

        args << {name: name, type: type_str}
        pos = advance_past_arg(block, cursor)
      end
      args
    end

    private def advance_past_arg(content : String, pos : Int32) : Int32
      depth = 0
      while pos < content.size
        ch = content[pos]
        case ch
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1
        when ','
          if depth == 0
            return pos + 1
          end
        end
        pos += 1
      end
      pos
    end

    private def read_type_reference(content : String, pos : Int32) : Tuple(String, Int32)
      start = pos
      depth = 0
      while pos < content.size
        ch = content[pos]
        if ch == '['
          depth += 1
          pos += 1
        elsif ch == ']'
          depth -= 1
          pos += 1
          if depth <= 0
            pos += 1 if pos < content.size && content[pos] == '!'
            break
          end
        elsif ch == '!' || ch == '_' || ch.ascii_alphanumeric?
          pos += 1
        elsif depth > 0 && (ch == ' ' || ch == '\t')
          pos += 1
        else
          break
        end
      end
      {content[start...pos].strip, pos}
    end

    private def read_directives(content : String, pos : Int32) : Tuple(Array(NamedTuple(name: String, args: String)), Int32)
      directives = [] of NamedTuple(name: String, args: String)
      last_committed = pos
      loop do
        scan_pos = skip_ws(content, pos)
        break if scan_pos >= content.size || content[scan_pos] != '@'
        scan_pos += 1
        name_match = content.match(/\G([A-Za-z_][A-Za-z0-9_]*)/, scan_pos)
        break if name_match.nil?
        name = name_match[1]
        scan_pos += name_match[0].size

        args_repr = ""
        if scan_pos < content.size && content[scan_pos] == '('
          args_block = extract_paren_block(content, scan_pos)
          if args_block
            args_repr = "(#{args_block.strip})"
            close = matching_close_index(content, scan_pos, '(', ')')
            scan_pos = close ? close + 1 : scan_pos + 1
          end
        end

        directives << {name: name, args: args_repr}
        pos = scan_pos
        last_committed = scan_pos
      end
      {directives, last_committed}
    end

    private def skip_default_value(content : String, pos : Int32) : Int32
      pos = skip_ws(content, pos)
      return pos if pos >= content.size
      depth = 0
      in_string = false
      while pos < content.size
        ch = content[pos]
        if in_string
          if ch == '"'
            in_string = false
          end
          pos += 1
          next
        end

        case ch
        when '"'
          in_string = true
          pos += 1
        when '[', '{', '('
          depth += 1
          pos += 1
        when ']', '}', ')'
          if depth == 0
            return pos
          end
          depth -= 1
          pos += 1
        when ','
          return pos if depth == 0
          pos += 1
        else
          if depth == 0 && (ch.ascii_whitespace? || ch == '@')
            return pos
          end
          pos += 1
        end
      end
      pos
    end

    private def line_number_at(sanitized : String, byte_pos : Int32) : Int32?
      return if byte_pos < 0 || byte_pos > sanitized.size
      sanitized[0, byte_pos].count('\n') + 1
    end
  end
end
