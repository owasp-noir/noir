require "../../../models/analyzer"

module Analyzer::Specification
  class Grpc < Analyzer
    # Represents a parsed protobuf message with its fields
    alias MessageFields = Array(Param)

    def analyze
      locator = CodeLocator.instance
      proto_files = locator.all("grpc-proto")
      return @result if proto_files.empty?

      # Request/response messages are frequently defined in a separate
      # (imported) `.proto`, so resolving params from the service file alone
      # drops them. Build one registry from every `.proto` in scope, keyed by
      # both simple and package-qualified name, and resolve against it.
      registry = build_message_registry

      proto_files.each do |proto_file|
        begin
          content = read_file_content(proto_file)
          parse_proto(content, proto_file, registry)
        rescue File::NotFoundError
          @logger.debug "Proto file not found during analysis, skipping: #{proto_file}"
        end
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
        rescue File::NotFoundError
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

      # Find message blocks using brace matching (supports nested messages/enums)
      content.scan(/\bmessage\s+(\w+)\s*\{/m) do |match|
        msg_name = match[1]
        start_pos = match.begin(0) || 0
        brace_pos = content.index('{', start_pos)
        next if brace_pos.nil?
        msg_body = extract_brace_block(content, brace_pos)
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
      # Find service blocks using brace matching
      content.scan(/\bservice\s+(\w+)\s*\{/m) do |service_match|
        service_name = service_match[1]
        start_pos = service_match.begin(0) || 0
        brace_pos = content.index('{', start_pos)
        next if brace_pos.nil?
        service_body = extract_brace_block(content, brace_pos)
        next if service_body.nil?

        parse_rpc_methods(service_body, file_path, package, service_name, registry, content)
      end
    end

    private def extract_brace_block(content : String, open_pos : Int32) : String?
      close = find_matching_delimiter(content, open_pos, '{', '}')
      return if close.nil?
      content[(open_pos + 1)..(close - 1)]
    end

    # Index of the delimiter that closes the `open_char` at `open_pos`, or nil
    # if unbalanced. String literals and `//` / `/* */` comments are skipped so
    # a delimiter inside them can't shift the depth. Works for `{}` and `[]`
    # (the array form of `additional_bindings`).
    private def find_matching_delimiter(content : String, open_pos : Int32, open_char : Char, close_char : Char) : Int32?
      depth = 0
      pos = open_pos
      in_string = false
      while pos < content.size
        ch = content[pos]
        if in_string
          # A quote closes the string only when preceded by an EVEN number of
          # backslashes (`\\"` toggles, `\"` does not).
          if ch == '"'
            bs = 0
            bp = pos - 1
            while bp >= 0 && content[bp] == '\\'
              bs += 1
              bp -= 1
            end
            in_string = false if bs.even?
          end
        elsif ch == '/' && pos + 1 < content.size && content[pos + 1] == '/'
          # Line comment: skip to EOL so a stray delimiter can't shift state.
          nl = content.index('\n', pos)
          pos = nl.nil? ? content.size : nl
          next
        elsif ch == '/' && pos + 1 < content.size && content[pos + 1] == '*'
          # Block comment: skip to the closing */.
          close = content.index("*/", pos + 2)
          pos = close.nil? ? content.size : close + 2
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

    private def parse_rpc_methods(service_body : String, file_path : String, package : String, service_name : String, registry : Hash(String, MessageFields), full_content : String)
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
            block = extract_brace_block(service_body, brace_pos)
            options_block = block || ""
          end
        end

        # Find line number using word boundary match
        line_number = find_line_number(full_content, method_name)
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

    private def parse_http_annotations(options_block : String) : Array(HttpMapping)
      mappings = [] of HttpMapping

      # Only the google.api.http option contributes HTTP routes. Scope to its
      # value block so a sibling option (e.g. openapiv2_operation, which can
      # also carry strings) can't leak a phantom method/path.
      return mappings unless options_block.includes?("google.api.http")
      rule_body = extract_http_rule_block(options_block)
      return mappings if rule_body.nil?

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

    # Returns the value block of `option (google.api.http) = { ... }`, or nil
    # when the annotation isn't in the supported brace form (e.g. the rarer
    # `(google.api.http).get = "..."` field syntax). The prefix guard keeps us
    # from latching onto a later, unrelated option's brace.
    private def extract_http_rule_block(options_block : String) : String?
      idx = options_block.index("google.api.http")
      return if idx.nil?
      after = idx + "google.api.http".size
      brace_pos = options_block.index('{', after)
      return if brace_pos.nil?
      return unless options_block[after...brace_pos].matches?(/\A[\s)=]*\z/)
      extract_brace_block(options_block, brace_pos)
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
      pos = 0
      while idx = rule_body.index(keyword, pos)
        cur = idx + keyword.size
        # Skip whitespace and an optional ':' between the keyword and its value.
        while cur < rule_body.size && (rule_body[cur].whitespace? || rule_body[cur] == ':')
          cur += 1
        end
        pos = idx + keyword.size
        next if cur >= rule_body.size

        case rule_body[cur]
        when '['
          # Array form: iterate each top-level { ... } object inside the [ ... ].
          array_close = find_matching_delimiter(rule_body, cur, '[', ']')
          next if array_close.nil?
          inner = rule_body[(cur + 1)...array_close]
          obj_pos = 0
          while obj_open = inner.index('{', obj_pos)
            obj_close = find_matching_delimiter(inner, obj_open, '{', '}')
            break if obj_close.nil?
            yield inner[(obj_open + 1)...obj_close]
            obj_pos = obj_close + 1
          end
        when '{'
          if body = extract_brace_block(rule_body, cur)
            yield body
          end
        end
      end
    end

    private def find_line_number(content : String, method_name : String) : Int32?
      # Hoisted out of the loop: an interpolated regex literal recompiles
      # (PCRE2 JIT) on every evaluation, i.e. once per line.
      rpc_regex = /\brpc\s+#{Regex.escape(method_name)}\s*\(/
      content.each_line.with_index do |line, index|
        next unless line.includes?(method_name)
        if line =~ rpc_regex
          return index + 1
        end
      end
      nil
    end
  end
end
