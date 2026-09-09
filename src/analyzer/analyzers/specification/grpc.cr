require "../../engines/specification_engine"

module Analyzer::Specification
  class Grpc < SpecificationEngine
    analyzer_for "grpc"

    # Represents a parsed protobuf message with its fields
    alias MessageFields = Array(Param)

    def analyze
      # `build_message_registry` reads and parses every `.proto` in the
      # codebase, so bail out before it when the detector registered no
      # service definitions to resolve against.
      return @result if CodeLocator.instance.all(Noir::LocatorKeys::GRPC_PROTO).empty?

      # Request/response messages are frequently defined in a separate
      # (imported) `.proto`, so resolving params from the service file alone
      # drops them. Build one registry from every `.proto` in scope, keyed by
      # both simple and package-qualified name, and resolve against it.
      registry = build_message_registry

      each_spec_file(Noir::LocatorKeys::GRPC_PROTO) do |proto_file|
        content = read_file_content(proto_file)
        parse_proto(content, proto_file, registry)
      end

      @result
    end

    # Parses messages from every `.proto` file the detector registered (not
    # just service files), so imported message types resolve. Each message is
    # stored under its simple name and its `package.Name` qualified form.
    private def build_message_registry : Hash(String, MessageFields)
      registry = {} of String => MessageFields
      CodeLocator.instance.files_by_extension(".proto").each do |proto_file|
        begin
          content = read_file_content(proto_file)
        rescue IO::Error
          next
        end
        clean = strip_comments(content)
        package = parse_package(clean)
        parse_messages(clean).each do |name, fields|
          registry[name] = fields
          registry["#{package}.#{name}"] = fields unless package.empty?
        end
      end
      registry
    end

    private def parse_proto(content : String, file_path : String, registry : Hash(String, MessageFields))
      # Strip comments before any structural parsing so a commented-out
      # `service` / `rpc` / `message` declaration is never mistaken for a
      # live definition (a false-positive source). Newlines are preserved,
      # so reported line numbers stay accurate.
      clean = strip_comments(content)
      package = parse_package(clean)
      parse_services(clean, file_path, package, registry)
    end

    # Resolves an rpc request type to its fields, tolerating leading dots,
    # fully-qualified names, same-package relative names, and imported simple
    # names. Same-package matches win over a bare simple-name match so two
    # messages that share a simple name across packages don't cross over.
    private def resolve_message(type_name : String, package : String, registry : Hash(String, MessageFields)) : MessageFields?
      name = type_name.lstrip('.')
      if name.includes?(".")
        if fields = registry[name]?
          return fields
        end
      else
        unless package.empty?
          if fields = registry["#{package}.#{name}"]?
            return fields
          end
        end
        if fields = registry[name]?
          return fields
        end
      end
      simple = name.includes?(".") ? name.rpartition(".")[2] : name
      registry[simple]?
    end

    # Replaces `//` line comments and `/* */` block comments with spaces
    # while preserving string literals, the total length, and every newline
    # (so positions/line numbers in the cleaned copy match the original).
    private def strip_comments(content : String) : String
      chars = content.chars
      size = chars.size
      String.build(content.bytesize) do |io|
        pos = 0
        in_string = false
        while pos < size
          ch = chars[pos]
          if in_string
            io << ch
            if ch == '"'
              # A quote closes the string only when preceded by an EVEN
              # number of backslashes (`\\"` toggles, `\"` does not).
              bs = 0
              bp = pos - 1
              while bp >= 0 && chars[bp] == '\\'
                bs += 1
                bp -= 1
              end
              in_string = false if bs.even?
            end
            pos += 1
          elsif ch == '/' && pos + 1 < size && chars[pos + 1] == '/'
            # Line comment: blank to EOL, leaving the newline for the next loop.
            while pos < size && chars[pos] != '\n'
              io << ' '
              pos += 1
            end
          elsif ch == '/' && pos + 1 < size && chars[pos + 1] == '*'
            # Block comment: blank through the closing `*/`, keeping newlines.
            io << ' ' << ' '
            pos += 2
            while pos < size && !(chars[pos] == '*' && pos + 1 < size && chars[pos + 1] == '/')
              io << (chars[pos] == '\n' ? '\n' : ' ')
              pos += 1
            end
            if pos < size
              io << ' ' << ' '
              pos += 2
            end
          elsif ch == '"'
            in_string = true
            io << ch
            pos += 1
          else
            io << ch
            pos += 1
          end
        end
      end
    end

    private def parse_package(content : String) : String
      if match = content.match(/^\s*package\s+([\w.]+)\s*;/m)
        match[1]
      else
        ""
      end
    end

    private def parse_messages(content : String) : Hash(String, MessageFields)
      messages = {} of String => MessageFields
      # One character array for the whole file, shared by every message's
      # brace match (see `find_matching_delimiter`). Built lazily so a
      # `.proto` with no message declarations pays nothing.
      chars = nil.as(Array(Char)?)

      # Find message blocks using brace matching (supports nested messages/enums)
      content.scan(/\bmessage\s+(\w+)\s*\{/m) do |match|
        msg_name = match[1]
        start_pos = match.begin(0) || 0
        brace_pos = content.index('{', start_pos)
        next if brace_pos.nil?
        file_chars = (chars ||= content.chars)
        msg_body = extract_brace_block(content, brace_pos, file_chars)
        next if msg_body.nil?

        fields = [] of Param

        msg_body.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?("//") || line.starts_with?("reserved") || line.starts_with?("option")
          # Skip nested message/enum/oneof declarations
          next if line.starts_with?("message ") || line.starts_with?("enum ") || line.starts_with?("oneof ")
          next if line == "}"

          # Match field patterns: [optional|repeated] type name = number;
          if field_match = line.match(/^\s*(?:optional\s+|repeated\s+|required\s+)?(?:map<[\w.]+\s*,\s*[\w.]+>|[\w.]+)\s+(\w+)\s*=\s*\d+/)
            fields << Param.new(field_match[1], "", "json")
          end
        end

        messages[msg_name] = fields
      end

      messages
    end

    private def parse_services(content : String, file_path : String, package : String, registry : Hash(String, MessageFields))
      # As in `parse_messages`: one shared character array for the file.
      # `content_lines` is likewise shared — `find_line_number` used to
      # re-walk every line of the document once per rpc method.
      chars = nil.as(Array(Char)?)
      content_lines = nil.as(Array(String)?)

      # Find service blocks using brace matching
      content.scan(/\bservice\s+(\w+)\s*\{/m) do |service_match|
        service_name = service_match[1]
        start_pos = service_match.begin(0) || 0
        brace_pos = content.index('{', start_pos)
        next if brace_pos.nil?
        file_chars = (chars ||= content.chars)
        service_body = extract_brace_block(content, brace_pos, file_chars)
        next if service_body.nil?

        file_lines = (content_lines ||= content.lines)
        parse_rpc_methods(service_body, file_path, package, service_name, registry, file_lines)
      end
    end

    private def extract_brace_block(content : String, open_pos : Int32,
                                    chars : Array(Char) = content.chars) : String?
      close = find_matching_delimiter(chars, open_pos, '{', '}')
      return if close.nil?
      content[(open_pos + 1)..(close - 1)]
    end

    # Index of the delimiter that closes the `open_char` at `open_pos`, or nil
    # if unbalanced. String literals and `//` / `/* */` comments are skipped so
    # a delimiter inside them can't shift the depth. Works for `{}` and `[]`
    # (the array form of `additional_bindings`).
    private def find_matching_delimiter(content : String, open_pos : Int32, open_char : Char, close_char : Char) : Int32?
      find_matching_delimiter(content.chars, open_pos, open_char, close_char)
    end

    # `chars` overload: the caller owns the materialised character array.
    #
    # This used to take the `String` and call `content.chars` itself, which
    # meant one `Array(Char)` the size of the whole file per message and per
    # service — O(messages x file size). `kubernetes`' 339 KB
    # `core/v1/generated.proto` alone paid for ~500 of them. Callers that
    # scan a buffer repeatedly now build the array once and hand it in.
    # Positions in and out are CHAR indices, as before.
    private def find_matching_delimiter(chars : Array(Char), open_pos : Int32, open_char : Char, close_char : Char) : Int32?
      size = chars.size
      depth = 0
      pos = open_pos
      in_string = false
      while pos < size
        ch = chars[pos]
        if in_string
          # A quote closes the string only when preceded by an EVEN number of
          # backslashes (`\\"` toggles, `\"` does not).
          if ch == '"'
            bs = 0
            bp = pos - 1
            while bp >= 0 && chars[bp] == '\\'
              bs += 1
              bp -= 1
            end
            in_string = false if bs.even?
          end
        elsif ch == '/' && pos + 1 < size && chars[pos + 1] == '/'
          # Line comment: skip to EOL so a stray delimiter can't shift state.
          nl = pos
          while nl < size && chars[nl] != '\n'
            nl += 1
          end
          pos = nl
          next
        elsif ch == '/' && pos + 1 < size && chars[pos + 1] == '*'
          # Block comment: skip to the closing */.
          cur = pos + 2
          while cur + 1 < size && !(chars[cur] == '*' && chars[cur + 1] == '/')
            cur += 1
          end
          pos = cur + 1 < size ? cur + 2 : size
          next
        elsif ch == '"'
          in_string = true
        elsif ch == open_char
          depth += 1
        elsif ch == close_char
          depth -= 1
          return pos if depth == 0
        end
        pos += 1
      end
      nil
    end

    private def parse_rpc_methods(service_body : String, file_path : String, package : String, service_name : String, registry : Hash(String, MessageFields), full_content_lines : Array(String))
      body_chars = nil.as(Array(Char)?)
      # Find each rpc definition and its associated options block
      service_body.scan(/\brpc\s+(\w+)\s*\(\s*(stream\s+)?(\.?\w+(?:\.\w+)*)\s*\)\s*returns\s*\(\s*(stream\s+)?(\.?\w+(?:\.\w+)*)\s*\)/m) do |rpc_match|
        method_name = rpc_match[1]
        request_streaming = !rpc_match[2]?.nil?
        request_type = rpc_match[3]
        response_streaming = !rpc_match[4]?.nil?
        # Find the options block after the rpc signature
        rpc_end = rpc_match.end(0) || 0
        remaining = service_body[rpc_end..]
        options_block = ""
        if remaining =~ /\A\s*\{/
          brace_pos = service_body.index('{', rpc_end)
          if brace_pos
            service_chars = (body_chars ||= service_body.chars)
            block = extract_brace_block(service_body, brace_pos, service_chars)
            options_block = block || ""
          end
        end

        # Find line number using word boundary match
        line_number = find_line_number(full_content_lines, method_name)
        details = Details.new(PathInfo.new(file_path, line_number))

        # Extract params from request message (resolved across imported files)
        params = [] of Param
        if msg_fields = resolve_message(request_type, package, registry)
          params = msg_fields.dup
        end

        # Check for gRPC-Gateway annotations
        http_mappings = parse_http_annotations(options_block)

        if http_mappings.empty?
          # Pure gRPC endpoint
          url = if package.empty?
                  "/#{service_name}/#{method_name}"
                else
                  "/#{package}.#{service_name}/#{method_name}"
                end
          endpoint = Endpoint.new(url, "POST", params, details)
          endpoint.protocol = "grpc"
          if request_streaming || response_streaming
            streaming_desc = String.build do |s|
              s << "client-streaming" if request_streaming
              s << ", " if request_streaming && response_streaming
              s << "server-streaming" if response_streaming
            end
            endpoint.add_tag(Tag.new("streaming", streaming_desc, "grpc_analyzer"))
          end
          @result << endpoint
        else
          # gRPC-Gateway: create HTTP endpoint(s)
          http_mappings.each do |mapping|
            http_method = mapping[:method]
            http_path = mapping[:path]

            # Extract path parameters (supports {var}, {var.field}, {var=pattern})
            gateway_params = [] of Param
            http_path.scan(/\{(\w+(?:\.\w+)*)(?:=[^}]*)?\}/) do |path_match|
              gateway_params << Param.new(path_match[1], "", "path")
            end

            # Determine how remaining message fields map to params. HEAD, like
            # GET/DELETE, carries no request body, so its fields go to the query.
            body_field = mapping[:body]?
            is_query_method = http_method == "GET" || http_method == "DELETE" || http_method == "HEAD"

            if body_field && !body_field.empty? && body_field != "*"
              # Specific field is the body
              gateway_params << Param.new(body_field, "", "json")
              # Remaining non-path, non-body fields become query params
              params.each do |p|
                next if p.name == body_field
                next if gateway_params.any? { |gp| gp.name == p.name }
                gateway_params << Param.new(p.name, "", "query")
              end
            elsif is_query_method && body_field.nil?
              # No body for GET/DELETE - remaining fields become query params
              params.each do |p|
                next if gateway_params.any? { |gp| gp.name == p.name }
                gateway_params << Param.new(p.name, "", "query")
              end
            else
              # body: "*" or non-GET/DELETE without specific body - fields go to body
              params.each do |p|
                next if gateway_params.any? { |gp| gp.name == p.name }
                gateway_params << p
              end
            end

            endpoint = Endpoint.new(http_path, http_method, gateway_params, details)
            @result << endpoint
          end
        end
      end
    end

    alias HttpMapping = NamedTuple(method: String, path: String, body: String?)

    # `google.api.http` has two textual spellings and real code uses both:
    #
    #   option (google.api.http) = { get: "/v1/x" body: "*" };  # brace form
    #
    #   option (google.api.http).get = "/v1/x";                 # field form
    #   option (google.api.http).body = "*";
    #
    # The field form is protobuf's generic "one field per statement" option
    # syntax, so a single HttpRule is spelled across several statements and
    # every one of them feeds the same rule. It is not a rarity: Argo CD
    # writes 70 of its 109 annotations that way, and reading only the brace
    # form dropped every one of those routes.
    #
    # An rpc that carries both spellings of the option is not valid protobuf
    # (protoc rejects the second as "already set"), but the two are parsed
    # independently here and both contribute, because for a scanner reading
    # whatever is on disk, dropping a written route is the worse failure.
    private def parse_http_annotations(options_block : String) : Array(HttpMapping)
      mappings = [] of HttpMapping

      # Only the google.api.http option contributes HTTP routes. Scope to its
      # value so a sibling option (e.g. openapiv2_operation, which can also
      # carry strings) can't leak a phantom method/path.
      return mappings unless options_block.includes?("google.api.http")

      chars = nil.as(Array(Char)?)
      # One group of mappings per rule, tagged with the offset the rule starts
      # at, so the emitted order follows the file even when forms are mixed.
      groups = [] of Tuple(Int32, Array(HttpMapping))
      field_rule = FieldFormRule.new

      key = "google.api.http"
      pos = 0
      while idx = options_block.index(key, pos)
        pos = idx + key.size
        cur = skip_blank(options_block, pos)
        # The extension is always parenthesised. Anything else — the name
        # quoted inside another option's string, say — is not an annotation.
        next unless char_at(options_block, cur) == ')'
        cur = skip_blank(options_block, cur + 1)

        if char_at(options_block, cur) == '.'
          file_chars = (chars ||= options_block.chars)
          apply_http_field(options_block, cur + 1, idx, file_chars, field_rule)
          next
        end

        cur = skip_blank(options_block, cur + 1) if char_at(options_block, cur) == '='
        next unless char_at(options_block, cur) == '{'
        file_chars = (chars ||= options_block.chars)
        rule_body = extract_brace_block(options_block, cur, file_chars)
        next if rule_body.nil?
        groups << {idx, mappings_from_rule_body(rule_body)}
      end

      if position = field_rule.position
        groups << {position, field_rule.mappings}
      end

      groups.sort_by! { |group| group[0] }
      groups.each { |group| mappings.concat(group[1]) }
      mappings
    end

    # Accumulator for the field form: each `option (google.api.http).<field>`
    # statement fills one slot, and together they describe one HttpRule.
    # `position` is the offset of the first statement that set anything, which
    # is where the assembled rule sorts among brace-form rules.
    private class FieldFormRule
      getter position : Int32?

      @bindings = [] of HttpMapping

      @method : String?
      @path : String?
      @body : String?
      @custom_kind : String?
      @custom_path : String?

      # `pattern` is a oneof in HttpRule, so a second verb would be invalid
      # protobuf; keep the first and ignore the rest rather than guessing.
      def set_verb(method : String, path : String, pos : Int32)
        return unless @method.nil?
        @method = method
        @path = path
        mark(pos)
      end

      def set_body(body : String, pos : Int32)
        @body ||= body
        mark(pos)
      end

      def set_custom_kind(kind : String, pos : Int32)
        @custom_kind ||= kind
        mark(pos)
      end

      def set_custom_path(path : String, pos : Int32)
        @custom_path ||= path
        mark(pos)
      end

      # additional_bindings is a repeated field: every statement appends.
      def add_bindings(new_bindings : Array(HttpMapping), pos : Int32)
        @bindings.concat(new_bindings)
        mark(pos)
      end

      def mappings : Array(HttpMapping)
        result = [] of HttpMapping
        method = @method
        path = @path
        kind = @custom_kind
        custom_path = @custom_path
        if method && path
          result << {method: method, path: path, body: @body}
        elsif kind && custom_path && !kind.empty?
          result << {method: kind.upcase, path: custom_path, body: @body}
        end
        result.concat(@bindings)
        result
      end

      private def mark(pos : Int32)
        @position = pos if @position.nil?
      end
    end

    # Applies one `option (google.api.http).<field> = <value>;` statement to
    # the rule being assembled. `name_pos` points just past the leading dot,
    # `stmt_pos` at the start of the option name (used only for ordering).
    private def apply_http_field(text : String, name_pos : Int32, stmt_pos : Int32,
                                 chars : Array(Char), rule : FieldFormRule)
      name_end = name_pos
      while ch = char_at(text, name_end)
        break unless ch.alphanumeric? || ch == '_' || ch == '.'
        name_end += 1
      end
      field = text[name_pos...name_end]
      return if field.empty?

      value_pos = skip_blank(text, name_end)
      return unless char_at(text, value_pos) == '='
      value_pos = skip_blank(text, value_pos + 1)

      case field
      when "get", "put", "post", "delete", "patch"
        if path = read_string_literal(text, value_pos)
          rule.set_verb(field.upcase, path, stmt_pos)
        end
      when "body"
        if body = read_string_literal(text, value_pos)
          rule.set_body(body, stmt_pos)
        end
      when "custom.kind"
        if kind = read_string_literal(text, value_pos)
          rule.set_custom_kind(kind, stmt_pos)
        end
      when "custom.path"
        if path = read_string_literal(text, value_pos)
          rule.set_custom_path(path, stmt_pos)
        end
      when "custom"
        # The whole CustomHttpPattern in one statement:
        # `.custom = { kind: "PURGE" path: "/v1/x" }`.
        return unless char_at(text, value_pos) == '{'
        return unless custom_body = extract_brace_block(text, value_pos, chars)
        if kind_match = custom_body.match(/\bkind\s*:\s*"([^"]*)"/)
          rule.set_custom_kind(kind_match[1], stmt_pos)
        end
        if path_match = custom_body.match(/\bpath\s*:\s*"([^"]*)"/)
          rule.set_custom_path(path_match[1], stmt_pos)
        end
      when "additional_bindings"
        each_rule_object(text, value_pos, chars) do |binding_body|
          rule.add_bindings(mappings_from_rule_body(binding_body), stmt_pos)
        end
      end
      # `selector` and `response_body` carry no route of their own and neither
      # changes how request fields map, so they are deliberately ignored.
    end

    # Turns one HttpRule body — the text between its braces — into mappings:
    # the primary route plus one per additional_binding.
    private def mappings_from_rule_body(rule_body : String) : Array(HttpMapping)
      mappings = [] of HttpMapping

      # The primary rule lives before the first additional_bindings; restrict
      # its `body:`/method scan there so a binding's body doesn't leak up.
      primary_scope =
        if ab_idx = rule_body.index("additional_bindings")
          rule_body[0...ab_idx]
        else
          rule_body
        end
      if primary = extract_rule_mapping(primary_scope)
        mappings << primary
      end

      # additional_bindings come in three textual shapes, all valid:
      #   additional_bindings { ... }      (no colon — googleapis style)
      #   additional_bindings: { ... }     (colon — grpc-gateway style)
      #   additional_bindings: [ {...}, {...} ]   (array of bindings)
      each_additional_binding_body(rule_body) do |binding_body|
        if mapping = extract_rule_mapping(binding_body)
          mappings << mapping
        end
      end

      mappings
    end

    # Extracts a single {method, path, body} mapping from one rule scope. Honors
    # the five standard verbs and the `custom: { kind: "VERB" path: "..." }`
    # form (HEAD/OPTIONS/TRACE and friends). Returns nil when no route is present.
    private def extract_rule_mapping(scope : String) : HttpMapping?
      body_value : String? = nil
      if body_match = scope.match(/\bbody\s*:\s*"([^"]*)"/)
        body_value = body_match[1]
      end

      # Word-boundary anchoring stops `widget:`/`path:` from matching `get`/`patch`.
      candidates = [] of Tuple(Int32, String, String)
      {% for http_method in ["get", "post", "put", "delete", "patch"] %}
        if match = scope.match(/\b{{ http_method.id }}\s*:\s*"([^"]*)"/)
          candidates << { (match.begin(0) || 0), {{ http_method.upcase }}, match[1] }
        end
      {% end %}
      unless candidates.empty?
        chosen = candidates.min_by { |c| c[0] }
        return {method: chosen[1], path: chosen[2], body: body_value}
      end

      # custom: { kind: "<verb>" path: "<template>" }
      if custom_match = scope.match(/\bcustom\s*:\s*\{/)
        custom_brace = scope.index('{', custom_match.begin(0) || 0)
        if custom_brace
          if custom_body = extract_brace_block(scope, custom_brace)
            kind_match = custom_body.match(/\bkind\s*:\s*"([^"]*)"/)
            path_match = custom_body.match(/\bpath\s*:\s*"([^"]*)"/)
            if kind_match && path_match && !kind_match[1].empty?
              return {method: kind_match[1].upcase, path: path_match[1], body: body_value}
            end
          end
        end
      end

      nil
    end

    # Yields each additional_bindings entry body, transparently handling the
    # no-colon, colon, and array (`[ {...}, {...} ]`) forms.
    private def each_additional_binding_body(rule_body : String, & : String ->)
      keyword = "additional_bindings"
      rule_chars = nil.as(Array(Char)?)
      pos = 0
      while idx = rule_body.index(keyword, pos)
        cur = idx + keyword.size
        pos = cur
        # Skip whitespace and an optional ':' between the keyword and its value.
        while cur < rule_body.size && (rule_body[cur].whitespace? || rule_body[cur] == ':')
          cur += 1
        end
        next if cur >= rule_body.size

        body_chars = (rule_chars ||= rule_body.chars)
        each_rule_object(rule_body, cur, body_chars) do |binding_body|
          yield binding_body
        end
      end
    end

    # Yields each `{ ... }` rule object starting at `pos`, accepting both the
    # single-object spelling and the `[ {...}, {...} ]` array spelling.
    private def each_rule_object(text : String, pos : Int32, chars : Array(Char), & : String ->)
      case char_at(text, pos)
      when '{'
        if body = extract_brace_block(text, pos, chars)
          yield body
        end
      when '['
        array_close = find_matching_delimiter(chars, pos, '[', ']')
        return if array_close.nil?
        inner = text[(pos + 1)...array_close]
        inner_chars = inner.chars
        obj_pos = 0
        while obj_open = inner.index('{', obj_pos)
          obj_close = find_matching_delimiter(inner_chars, obj_open, '{', '}')
          break if obj_close.nil?
          yield inner[(obj_open + 1)...obj_close]
          obj_pos = obj_close + 1
        end
      end
    end

    # Reads the protobuf string literal at `pos`, joining a run of adjacent
    # literals (`"/v1/" "things"` is one string in protobuf). Escapes are kept
    # verbatim, matching how the brace-form scan reads paths.
    private def read_string_literal(text : String, pos : Int32) : String?
      return unless char_at(text, pos) == '"'
      size = text.size
      cur = pos
      parts = String::Builder.new
      while cur < size && text[cur] == '"'
        cur += 1
        start = cur
        while cur < size
          ch = text[cur]
          break if ch == '"'
          cur += (ch == '\\' ? 2 : 1)
        end
        return if cur >= size
        parts << text[start...cur]
        cur = skip_blank(text, cur + 1)
      end
      parts.to_s
    end

    private def char_at(text : String, pos : Int32) : Char?
      pos >= 0 && pos < text.size ? text[pos] : nil
    end

    private def skip_blank(text : String, pos : Int32) : Int32
      cur = pos
      while ch = char_at(text, cur)
        break unless ch.whitespace?
        cur += 1
      end
      cur
    end

    private def find_line_number(lines : Array(String), method_name : String) : Int32?
      # Hoisted out of the loop: an interpolated regex literal recompiles
      # (PCRE2 JIT) on every evaluation, i.e. once per line.
      rpc_regex = /\brpc\s+#{Regex.escape(method_name)}\s*\(/
      lines.each_with_index do |line, index|
        next unless line.includes?(method_name)
        if line =~ rpc_regex
          return index + 1
        end
      end
      nil
    end
  end
end
