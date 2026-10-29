require "../../engines/go_engine"

module Analyzer::Go
  # Huma (https://huma.rocks/) is an OpenAPI-first Go framework
  # where every operation is registered through
  #   huma.Register(api, huma.Operation{Method: ..., Path: ...}, handler)
  # The Operation literal carries method/path verbatim, and the
  # handler's Input struct fields declare parameter shape via
  # tags (`path:"id"`, `query:"limit"`, `header:"X-Auth"`, plus
  # a `Body` field for request bodies). That makes extraction
  # unusually precise compared to other Go routers.
  class Huma < GoEngine
    analyzer_for "go_huma"

    IMPORT_MARKER = "github.com/danielgtaylor/huma"

    # One precompiled matcher instead of a `String#includes?` scan per
    # `.go` file: `includes?` runs Rabin-Karp over the whole buffer and
    # the marker is absent in the overwhelming majority of files in a
    # polyglot repo, so every one of them pays the full scan. See
    # `Analyzer#content_matches?`.
    IMPORT_MARKER_RE = Regex.union(IMPORT_MARKER)

    # Tags we lift from Input struct fields onto endpoint params.
    PARAM_TAG_KINDS = {
      "path"   => "path",
      "query"  => "query",
      "header" => "header",
      "cookie" => "cookie",
    }

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile) — precompile the fixed tag matchers once
    # at load time instead of per struct field.
    PARAM_TAG_PATTERNS = PARAM_TAG_KINDS.map do |go_tag, param_type|
      {param_type, /#{go_tag}:"([^"]+)"/}
    end

    # Huma v2's typed convenience helpers — `huma.Get(api, "/path",
    # handler)` and friends — register an operation without the verbose
    # `huma.Register(api, huma.Operation{...}, handler)` literal. The verb
    # is the method name; the path is the SECOND argument (the first is
    # the API/group). Mapped here so the call walker can decode them
    # alongside `huma.Register`.
    SUGAR_VERBS = {
      "huma.Get"     => "GET",
      "huma.Post"    => "POST",
      "huma.Put"     => "PUT",
      "huma.Patch"   => "PATCH",
      "huma.Delete"  => "DELETE",
      "huma.Head"    => "HEAD",
      "huma.Options" => "OPTIONS",
    }

    struct StructField
      property name : String
      property tag : String
      # The field's type as written (`User`, `*Payload`, `struct {...}`).
      property type_text : String
      # The fields of an inline `struct {...}` type (`Body struct { Name string }`).
      property inline_fields : Array(StructField)?

      def initialize(@name, @tag, @type_text = "", @inline_fields = nil)
      end
    end

    def analyze
      result = [] of Endpoint

      package_files = Hash(String, Array(String)).new
      file_contents_cache = Hash(String, String).new

      get_files_by_extension(".go").each do |scan_path|
        next if go_test_path?(scan_path)
        begin
          dir = File.dirname(scan_path)
          package_files[dir] ||= [] of String
          package_files[dir] << scan_path
          file_contents_cache[scan_path] = read_file_content(scan_path)
        rescue IO::Error
          # skip
        end
      end

      # Per-directory struct table: name => [StructField, ...]
      package_structs = Hash(String, Hash(String, Array(StructField))).new
      file_contents_cache.each do |path, content|
        dir = File.dirname(path)
        package_structs[dir] ||= Hash(String, Array(StructField)).new
        collect_struct_definitions(content).each do |name, fields|
          package_structs[dir][name] ||= fields
        end
      end

      mutex = Mutex.new
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)

        content = file_contents_cache[path]? || read_file_content(path)
        next unless content_matches?(content, IMPORT_MARKER_RE)

        dir = File.dirname(path)
        structs = package_structs[dir]? || Hash(String, Array(StructField)).new

        endpoints = extract_huma_endpoints(content, path, structs)
        next if endpoints.empty?

        mutex.synchronize do
          endpoints.each { |ep| result << ep }
        end
      end

      result
    end

    # Walks the Go AST for every `huma.Register(...)` call, decoding
    # method/path from the Operation composite literal and resolving
    # the handler's Input struct fields for param classification.
    private def extract_huma_endpoints(source : String, path : String,
                                       structs : Hash(String, Array(StructField))) : Array(Endpoint)
      endpoints = [] of Endpoint
      Noir::TreeSitter.parse_go(source) do |root|
        groups = collect_huma_groups(root, source)
        walk_calls(root) do |call|
          func = Noir::TreeSitter.field(call, "function")
          next if func.nil?
          func_text = Noir::TreeSitter.node_text(func, source)
          sugar_verb = SUGAR_VERBS[func_text]?
          # `sse.Register(api, op, eventTypes, handler)` takes the same
          # Operation literal, with the handler one argument later.
          sse = func_text == "sse.Register"
          next unless func_text == "huma.Register" || sse || sugar_verb

          args = Noir::TreeSitter.field(call, "arguments")
          next if args.nil?

          # `route_path` keeps an empty-string default (a sugar call with
          # too few args leaves it unset); `method` is assigned on every
          # branch below, so it needs no initializer.
          route_path = ""
          handler_node : LibTreeSitter::TSNode? = nil
          api_node : LibTreeSitter::TSNode? = nil

          if sugar_verb
            # huma.Get(api, "/path", handler) — path@1, handler@2.
            method = sugar_verb
            arg_index = 0
            Noir::TreeSitter.each_named_arg(args) do |arg|
              case arg_index
              when 0 then api_node = arg
              when 1 then route_path = decode_string_value(arg, source) || ""
              when 2 then handler_node = arg
              end
              arg_index += 1
            end
          else
            # huma.Register(api, huma.Operation{...}, handler) —
            # Operation literal@1, handler@2.
            op_node : LibTreeSitter::TSNode? = nil
            arg_index = 0
            handler_index = sse ? 3 : 2
            Noir::TreeSitter.each_named_arg(args) do |arg|
              case arg_index
              when 0             then api_node = arg
              when 1             then op_node = arg
              when handler_index then handler_node = arg
              end
              arg_index += 1
            end
            operation_arg = op_node
            next if operation_arg.nil?
            method, route_path = decode_operation(operation_arg, source)
          end

          next if method.empty? || route_path.empty?
          # An operation registered on a `huma.NewGroup(api, "/v1")` group is
          # served under each of the group's prefixes.
          prefixes = api_node.try { |api_arg| Noir::TreeSitter.node_type(api_arg) == "identifier" ? groups[Noir::TreeSitter.node_text(api_arg, source)]? : nil }
          route_paths = prefixes ? prefixes.map { |prefix| "#{prefix.rstrip('/')}#{route_path}" } : [route_path]

          row = Noir::TreeSitter.node_start_row(call) + 1
          fields = handler_node.try { |handler_arg| input_fields(handler_arg, source, structs) }
          route_paths.each do |url|
            endpoint = Endpoint.new(url, method.upcase, Details.new(PathInfo.new(path, row)))
            fields.try &.each { |field| push_field_param(endpoint, field, structs) }
            endpoints << endpoint
          end
        end
      end
      endpoints
    end

    # Walks `composite_literal` (the `huma.Operation{...}` expression)
    # and returns `{method, path}` decoded from the keyed elements.
    # `Method` accepts either a string literal or a selector like
    # `http.MethodGet`; `Path` is always a string literal.
    private def decode_operation(node : LibTreeSitter::TSNode, source : String) : Tuple(String, String)
      method = ""
      path = ""

      type_node = Noir::TreeSitter.field(node, "type")
      type_text = type_node ? Noir::TreeSitter.node_text(type_node, source) : ""
      return {method, path} unless type_text.includes?("Operation")

      body = Noir::TreeSitter.field(node, "body")
      return {method, path} if body.nil?

      Noir::TreeSitter.each_named_child(body) do |child|
        next unless Noir::TreeSitter.node_type(child) == "keyed_element"

        # tree-sitter-go wraps each side of a keyed_element in a
        # `literal_element` container; unwrap to reach the actual key
        # identifier and the value expression.
        key_node = Noir::TreeSitter.field(child, "key")
        value_field = Noir::TreeSitter.field(child, "value")
        # When the field names aren't populated, fall back to the
        # first two named children.
        if key_node.nil? || value_field.nil?
          children = [] of LibTreeSitter::TSNode
          Noir::TreeSitter.each_named_child(child) { |kv| children << kv }
          next if children.size < 2
          key_node ||= children[0]
          value_field ||= children[1]
        end

        key = key_node
        val_field = value_field
        next if key.nil? || val_field.nil?

        key_text = unwrap_literal_text(key, source)
        value = unwrap_literal_node(val_field)
        next if value.nil?

        case key_text
        when "Method"
          method = decode_method_value(value, source)
        when "Path"
          decoded = decode_string_value(value, source)
          path = decoded if decoded
        end
      end

      {method, path}
    end

    # `Method` can be:
    #   - "GET" / "POST" — raw string literal
    #   - http.MethodGet — selector_expression mapped via lookup table
    private def decode_method_value(node : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(node)
      when "interpreted_string_literal", "raw_string_literal"
        text = Noir::TreeSitter.node_text(node, source)
        text.gsub(/^["`]|["`]$/, "")
      when "selector_expression"
        selector = Noir::TreeSitter.node_text(node, source)
        HTTP_METHOD_CONSTANTS[selector]? || ""
      else
        ""
      end
    end

    private def decode_string_value(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "interpreted_string_literal", "raw_string_literal"
        Noir::TreeSitter.node_text(node, source).gsub(/^["`]|["`]$/, "")
      end
    end

    HTTP_METHOD_CONSTANTS = {
      "http.MethodGet"     => "GET",
      "http.MethodPost"    => "POST",
      "http.MethodPut"     => "PUT",
      "http.MethodPatch"   => "PATCH",
      "http.MethodDelete"  => "DELETE",
      "http.MethodHead"    => "HEAD",
      "http.MethodOptions" => "OPTIONS",
      "http.MethodConnect" => "CONNECT",
      "http.MethodTrace"   => "TRACE",
      "http.MethodQuery"   => "QUERY",
    }

    # `v1 := huma.NewGroup(api, "/v1")` (and groups of groups) -> `{"v1" => ["/v1"]}`.
    # `NewGroup` takes several prefixes (`huma.NewGroup(api, "/v1", "/api/v1")`).
    # A name bound to different prefixes in one file (reused in two
    # functions) is ambiguous and left out, as is a group rebound onto
    # itself (`api = huma.NewGroup(api, "/v1")`), whose earlier routes have
    # no prefix.
    private def collect_huma_groups(root : LibTreeSitter::TSNode, source : String) : Hash(String, Array(String))
      groups = Hash(String, Array(String)).new
      ambiguous = Set(String).new
      walk_node(root) do |node|
        next unless {"short_var_declaration", "assignment_statement"}.includes?(Noir::TreeSitter.node_type(node))
        left = Noir::TreeSitter.field(node, "left").try { |l| Noir::TreeSitter.first_named_child(l) }
        call = Noir::TreeSitter.field(node, "right").try { |r| Noir::TreeSitter.first_named_child(r) }
        next unless left && call && Noir::TreeSitter.node_type(left) == "identifier" && Noir::TreeSitter.node_type(call) == "call_expression"
        next unless Noir::TreeSitter.field(call, "function").try { |f| Noir::TreeSitter.node_text(f, source) } == "huma.NewGroup"
        args = [] of LibTreeSitter::TSNode
        Noir::TreeSitter.field(call, "arguments").try { |a| Noir::TreeSitter.each_named_arg(a) { |arg| args << arg } }
        name = Noir::TreeSitter.node_text(left, source)
        parent_name = args[0]?.try { |arg| Noir::TreeSitter.node_type(arg) == "identifier" ? Noir::TreeSitter.node_text(arg, source) : nil }
        next if parent_name == name || (parent_name && ambiguous.includes?(parent_name))
        own = args[1..]?.try(&.compact_map { |arg| decode_string_value(arg, source) }) || [] of String
        next if own.empty?
        parents = parent_name.try { |parent_key| groups[parent_key]? } || [""]
        value = parents.flat_map { |parent| own.map { |prefix| "#{parent.rstrip('/')}#{prefix}" } }
        if (old = groups[name]?) && old != value
          ambiguous << name
        else
          groups[name] = value
        end
      end
      ambiguous.each { |name| groups.delete(name) }
      groups
    end

    # The handler's Input struct fields: an inline `*struct {...}` parameter
    # read in place, a named one looked up in the package's struct table.
    private def input_fields(node : LibTreeSitter::TSNode, source : String,
                             structs : Hash(String, Array(StructField))) : Array(StructField)?
      if (type_node = input_type_node(node)) && (struct_node = struct_type_of(type_node))
        return extract_struct_fields(struct_node, source)
      end
      extract_input_struct_name(node, source).try { |name| structs[name]? }
    end

    # The second parameter's type node of a handler func literal.
    private def input_type_node(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      return unless Noir::TreeSitter.node_type(node) == "func_literal"
      params = Noir::TreeSitter.field(node, "parameters") || return
      decls = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(params) do |decl|
        decls << decl if Noir::TreeSitter.node_type(decl) == "parameter_declaration"
      end
      decls[1]?.try { |decl| Noir::TreeSitter.field(decl, "type") }
    end

    # `struct {...}` or `*struct {...}` -> the `struct_type` node.
    private def struct_type_of(type_node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      case Noir::TreeSitter.node_type(type_node)
      when "struct_type"  then type_node
      when "pointer_type" then Noir::TreeSitter.first_named_child(type_node).try { |inner| struct_type_of(inner) }
      end
    end

    # Pulls the Input struct name out of the handler function literal.
    # Huma handlers look like:
    #   func(ctx context.Context, input *FooInput) (*FooOutput, error) { ... }
    # We want `FooInput` (second parameter, dereferenced).
    private def extract_input_struct_name(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "func_literal"

      params = Noir::TreeSitter.field(node, "parameters")
      return if params.nil?

      decls = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(params) do |decl|
        decls << decl if Noir::TreeSitter.node_type(decl) == "parameter_declaration"
      end
      return if decls.size < 2

      type_node = Noir::TreeSitter.field(decls[1], "type")
      return if type_node.nil?

      text = Noir::TreeSitter.node_text(type_node, source).strip
      text = text.lchop('*')
      # Strip package qualifier (e.g., "pkg.Foo" -> "Foo") — Huma input
      # types are nearly always local to the package, so we keep the
      # last identifier segment for the lookup.
      if dot = text.rindex('.')
        text = text[(dot + 1)..]
      end
      text.empty? ? nil : text
    end

    # Top-level type-declaration scan that produces a name => fields
    # map for every `type X struct { ... }` in `source`. Fields are
    # captured with their raw tag string so callers can pull whichever
    # tag namespace applies (path, query, header, cookie, json).
    #
    # We walk the tree-sitter tree rather than regex the source because
    # Huma input structs can be nested or embedded, and regex would
    # mis-bind tag strings on long field lines.
    private def collect_struct_definitions(source : String) : Hash(String, Array(StructField))
      result = Hash(String, Array(StructField)).new
      Noir::TreeSitter.parse_go(source) do |root|
        walk_node(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "type_spec"
          name_node = Noir::TreeSitter.field(node, "name")
          type_node = Noir::TreeSitter.field(node, "type")
          next if name_node.nil? || type_node.nil?
          nn = name_node
          tn = type_node
          next unless Noir::TreeSitter.node_type(tn) == "struct_type"

          struct_name = Noir::TreeSitter.node_text(nn, source)
          fields = extract_struct_fields(tn, source)
          result[struct_name] ||= fields
        end
      end
      result
    end

    private def extract_struct_fields(struct_node : LibTreeSitter::TSNode, source : String) : Array(StructField)
      fields = [] of StructField
      # `struct_type` has no `fields` field-name in tree-sitter-go's
      # grammar; the field declaration list is a plain named child.
      field_list = nil
      Noir::TreeSitter.each_named_child(struct_node) do |c|
        if Noir::TreeSitter.node_type(c) == "field_declaration_list"
          field_list = c
          break
        end
      end
      fl = field_list
      return fields if fl.nil?

      Noir::TreeSitter.each_named_child(fl) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "field_declaration"

        tag = ""
        if tag_node = Noir::TreeSitter.field(decl, "tag")
          tag = Noir::TreeSitter.node_text(tag_node, source)
          tag = tag.gsub(/^[`"]|[`"]$/, "")
        end

        if name_node = Noir::TreeSitter.field(decl, "name")
          field_name = Noir::TreeSitter.node_text(name_node, source)
          field_type = Noir::TreeSitter.field(decl, "type")
          inline = field_type.try { |t| struct_type_of(t) }.try { |st| extract_struct_fields(st, source) }
          fields << StructField.new(field_name, tag, field_type.try { |t| Noir::TreeSitter.node_text(t, source) } || "", inline)
        elsif type_node = Noir::TreeSitter.field(decl, "type")
          # Embedded field — name comes from the type itself; we don't
          # need to descend into embedded structs for Huma input types
          # in practice (huma.Operation isn't extended that way), so
          # leave a placeholder so the slot is preserved.
          field_name = Noir::TreeSitter.node_text(type_node, source)
          fields << StructField.new(field_name, tag)
        end
      end
      fields
    end

    private def push_field_param(endpoint : Endpoint, field : StructField, structs : Hash(String, Array(StructField)))
      tag = field.tag
      if field.name == "Body"
        # A struct body (inline, or a package struct) is listed by its JSON
        # field names; anything else (`Body []User`, `Body string`) as `body`.
        body_fields = field.inline_fields || structs[field.type_text.lchop('*')]?
        names = body_fields.try &.compact_map { |f| json_name(f) } || [] of String
        names = ["body"] if names.empty?
        names.each do |name|
          param = Param.new(name, "", "json")
          endpoint.params << param unless endpoint.params.includes?(param)
        end
        return
      end

      PARAM_TAG_PATTERNS.each do |param_type, tag_regex|
        if match = tag.match(tag_regex)
          param = Param.new(match[1], "", param_type)
          endpoint.params << param unless endpoint.params.includes?(param)
          return
        end
      end

      # Untagged fields on input structs default to "body" in Huma's
      # implicit conventions only when they're the sole field; we err
      # on the side of not emitting them to avoid false positives.
    end

    # The JSON key encoding/json gives a struct field: its `json` tag name,
    # else the field name; nil for `json:"-"`, an unexported field, or an
    # embedded one (recorded with no type; its promoted fields are not read).
    private def json_name(field : StructField) : String?
      return if field.type_text.empty? || !field.name[0]?.try(&.uppercase?)
      if m = field.tag.match(/json:"([^",]*)/)
        return if m[1] == "-"
        return m[1] unless m[1].empty?
      end
      field.name
    end

    # `literal_element` is tree-sitter-go's container for keyed-element
    # children. Strip it so callers see the underlying expression
    # (identifier, string literal, selector_expression, etc.).
    private def unwrap_literal_node(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      if Noir::TreeSitter.node_type(node) == "literal_element"
        first = nil
        Noir::TreeSitter.each_named_child(node) do |c|
          first ||= c
        end
        return first
      end
      node
    end

    private def unwrap_literal_text(node : LibTreeSitter::TSNode, source : String) : String
      inner = unwrap_literal_node(node)
      return "" if inner.nil?
      Noir::TreeSitter.node_text(inner, source)
    end

    private def walk_calls(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "call_expression"
        yield node
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_calls(child, &block)
      end
    end

    private def walk_node(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      yield node
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_node(child, &block)
      end
    end
  end
end
