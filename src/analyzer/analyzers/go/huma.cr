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
    IMPORT_MARKER = "github.com/danielgtaylor/huma"

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

    private struct StructField
      property name : String
      property tag : String

      def initialize(@name, @tag)
      end
    end

    def analyze
      result = [] of Endpoint

      package_files = Hash(String, Array(String)).new
      file_contents_cache = Hash(String, String).new

      get_files_by_extension(".go").each do |scan_path|
        next if File.directory?(scan_path)
        next if GoEngine.go_test_file?(scan_path)
        begin
          dir = File.dirname(scan_path)
          package_files[dir] ||= [] of String
          package_files[dir] << scan_path
          file_contents_cache[scan_path] = read_file_content(scan_path)
        rescue File::NotFoundError
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

      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        mutex = Mutex.new
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            get_files_by_extension(".go").each { |file| channel.send(file) }
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if GoEngine.go_test_file?(path)
                  next unless File.exists?(path)

                  content = file_contents_cache[path]? || read_file_content(path)
                  next unless content.includes?(IMPORT_MARKER)

                  dir = File.dirname(path)
                  structs = package_structs[dir]? || Hash(String, Array(StructField)).new

                  endpoints = extract_huma_endpoints(content, path, structs)
                  next if endpoints.empty?

                  mutex.synchronize do
                    endpoints.each { |ep| result << ep }
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
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
        walk_calls(root) do |call|
          func = Noir::TreeSitter.field(call, "function")
          next if func.nil?
          func_text = Noir::TreeSitter.node_text(func, source)
          sugar_verb = SUGAR_VERBS[func_text]?
          next unless func_text == "huma.Register" || sugar_verb

          args = Noir::TreeSitter.field(call, "arguments")
          next if args.nil?

          # `route_path` keeps an empty-string default (a sugar call with
          # too few args leaves it unset); `method` is assigned on every
          # branch below, so it needs no initializer.
          route_path = ""
          handler_node : LibTreeSitter::TSNode? = nil

          if sugar_verb
            # huma.Get(api, "/path", handler) — path@1, handler@2.
            method = sugar_verb
            arg_index = 0
            Noir::TreeSitter.each_named_child(args) do |arg|
              case arg_index
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
            Noir::TreeSitter.each_named_child(args) do |arg|
              case arg_index
              when 1 then op_node = arg
              when 2 then handler_node = arg
              end
              arg_index += 1
            end
            operation_arg = op_node
            next if operation_arg.nil?
            method, route_path = decode_operation(operation_arg, source)
          end

          next if method.empty? || route_path.empty?

          row = Noir::TreeSitter.node_start_row(call) + 1
          details = Details.new(PathInfo.new(path, row))
          endpoint = Endpoint.new(route_path, method.upcase, details)

          if handler_arg = handler_node
            input_type = extract_input_struct_name(handler_arg, source)
            if input_type && (fields = structs[input_type]?)
              fields.each do |field|
                push_field_param(endpoint, field)
              end
            end
          end

          endpoints << endpoint
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
    }

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
          fields << StructField.new(field_name, tag)
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

    private def push_field_param(endpoint : Endpoint, field : StructField)
      tag = field.tag
      if field.name == "Body"
        param = Param.new("body", "", "json")
        endpoint.params << param unless endpoint.params.includes?(param)
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
