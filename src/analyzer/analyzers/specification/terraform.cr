require "../../../models/analyzer"

module Analyzer::Specification
  # Extracts HTTP endpoints from Terraform / OpenTofu configurations that
  # declare AWS API Gateway routes. Two shapes are covered, mirroring the
  # CloudFormation analyzer:
  #
  #   * API Gateway v2 (HTTP / WebSocket) — `aws_apigatewayv2_route` carries a
  #     self-contained `route_key = "GET /path"`, so it resolves per file.
  #   * API Gateway v1 (REST) — `aws_api_gateway_resource` + `aws_api_gateway_method`
  #     form a reference graph. Terraform merges every `.tf` file in a module
  #     directory into one config, so the graph is resolved per directory, not
  #     per file.
  #
  # Both HCL (`.tf`) and Terraform JSON (`.tf.json`) inputs are supported.
  class Terraform < Analyzer
    METHOD_ANY   = "ANY"
    HTTP_METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "ANY"}

    RESOURCE_TYPE_V2     = "aws_apigatewayv2_route"
    RESOURCE_TYPE_REST_R = "aws_api_gateway_resource"
    RESOURCE_TYPE_REST_M = "aws_api_gateway_method"

    # Attributes the analyzer reads out of a resource body. Everything else is
    # skipped while scanning.
    #
    # `route_key` / `path_part` / `http_method` are only meaningful as literal
    # strings — a computed value (`each.value.method`, `"${var.path}"`) can't be
    # resolved statically, so they are captured from quoted strings only.
    # `resource_id` / `parent_id` are by nature references into the resource
    # graph, so they are captured from bare expressions too.
    TARGET_ATTRS = {"route_key", "path_part", "parent_id", "resource_id", "http_method"}
    REF_ATTRS    = {"parent_id", "resource_id"}

    # A parsed `resource "type" "name" { ... }` block with only the attributes
    # in TARGET_ATTRS captured.
    record TfResource, type : String, name : String, attrs : Hash(String, String)
    # A REST resource node for path reconstruction.
    record RestNode, name : String, path_part : String, parent : String?

    def analyze
      spec_files = CodeLocator.instance.all("terraform-spec")
      return @result unless spec_files.is_a?(Array(String))

      # Group files by module directory. A REST resource and the method that
      # references it routinely live in different files of the same module.
      by_dir = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
      spec_files.each do |path|
        next unless File.exists?(path)
        by_dir[File.dirname(path)] << path
      end

      by_dir.each_value { |paths| process_module(paths) }

      @result
    end

    private def process_module(paths : Array(String))
      parsed = [] of {details: Details, resources: Array(TfResource)}
      paths.each do |path|
        content = read_file_content(path)
        begin
          parsed << {details: Details.new(PathInfo.new(path)), resources: parse_file(path, content)}
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      # v2 routes are self-contained, attribute them to their own file.
      parsed.each { |entry| process_apigatewayv2(entry[:resources], entry[:details]) }

      # v1 REST graph: build one resource map for the whole module directory,
      # then walk parents for each method.
      rest_nodes = {} of String => RestNode
      parsed.each do |entry|
        entry[:resources].each do |res|
          next unless res.type == RESOURCE_TYPE_REST_R
          rest_nodes[res.name] = RestNode.new(res.name, res.attrs["path_part"]? || "", res.attrs["parent_id"]?)
        end
      end

      parsed.each { |entry| process_apigateway_rest(entry[:resources], rest_nodes, entry[:details]) }
    end

    private def process_apigatewayv2(resources : Array(TfResource), details : Details)
      resources.each do |res|
        next unless res.type == RESOURCE_TYPE_V2
        route_key = res.attrs["route_key"]?
        next if route_key.nil? || route_key.empty?

        method, path = parse_route_key(route_key)
        next if path.nil? || path.empty?
        next unless HTTP_METHODS.includes?(method)

        endpoint = Endpoint.new(path, method, details)
        endpoint.add_tag(Tag.new("terraform-apigateway", "httpapi", "terraform_analyzer"))
        @result << endpoint
      end
    end

    private def process_apigateway_rest(resources : Array(TfResource), rest_nodes : Hash(String, RestNode), details : Details)
      resources.each do |res|
        next unless res.type == RESOURCE_TYPE_REST_M
        resource_id = res.attrs["resource_id"]?
        next if resource_id.nil? || resource_id.empty?

        # Only a literal HTTP verb is trustworthy; a computed `http_method`
        # (`each.value.method`) is dropped rather than guessed.
        resolved_method = (res.attrs["http_method"]? || "").upcase
        resolved_method = METHOD_ANY if resolved_method == "*"
        next unless HTTP_METHODS.includes?(resolved_method)

        path = build_rest_path(resource_id, rest_nodes)
        next if path.nil?

        endpoint = Endpoint.new(path, resolved_method, details)
        endpoint.add_tag(Tag.new("terraform-apigateway", "rest", "terraform_analyzer"))
        @result << endpoint
      end
    end

    # "GET /items/{id}" -> {"GET", "/items/{id}"}. Returns a nil path for
    # anything that isn't a concrete "METHOD /path": WebSocket / catch-all keys
    # (`$default`, `$connect`, `$disconnect`), bare references
    # (`each.value.route_key`), and interpolation-only paths (`"GET ${var.x}"`).
    # A path that merely embeds interpolation (`GET /items/${var.id}`) is kept.
    private def parse_route_key(route_key : String) : Tuple(String, String?)
      rk = route_key.strip
      return {METHOD_ANY, nil} if rk.empty? || rk.starts_with?('$')

      parts = rk.split(/\s+/, 2)
      return {METHOD_ANY, nil} unless parts.size == 2 && parts[1].starts_with?('/')
      {parts[0].upcase, parts[1]}
    end

    # Walk `parent_id` references from the method's `resource_id` up to the REST
    # API root, assembling the path. Returns nil when the reference points at
    # neither a known resource nor the API root.
    private def build_rest_path(resource_id : String, rest_nodes : Hash(String, RestNode)) : String?
      name = ref_resource_name(resource_id)
      if name.nil?
        return "/" if references_root?(resource_id)
        return
      end

      segments = [] of String
      visited = Set(String).new
      current = name
      while current
        break if visited.includes?(current)
        visited << current
        node = rest_nodes[current]?
        break unless node
        # A missing or interpolation-bearing `path_part` means the segment is
        # computed; the whole path can't be reconstructed reliably, so bail out
        # rather than emit a path with a hole in it.
        pp = node.path_part
        return if pp.empty? || pp.includes?("${")
        segments.unshift(pp)
        parent = node.parent
        break if parent.nil?
        current = ref_resource_name(parent)
      end

      # Empty segments here means the starting resource was never found in the
      # module (child-module ref, parse failure, for_each-indexed ref); the path
      # is unknown, so skip rather than emit a spurious "/". The genuine
      # method-on-root case is already handled above via `references_root?`.
      return if segments.empty?
      "/" + segments.join('/')
    end

    # `aws_api_gateway_resource.items.id` -> "items". nil for anything else
    # (root reference, unknown resource type, literal id, …).
    private def ref_resource_name(raw : String) : String?
      chain = strip_interpolation(raw).split('.')
      return chain[1]? if chain[0]? == RESOURCE_TYPE_REST_R
      nil
    end

    private def references_root?(raw : String) : Bool
      s = strip_interpolation(raw)
      s.includes?("aws_api_gateway_rest_api") && s.includes?("root_resource_id")
    end

    # Terraform JSON wraps references in interpolation: `"${aws_x.y.id}"`.
    private def strip_interpolation(raw : String) : String
      s = raw.strip
      if s.starts_with?("${") && s.ends_with?('}')
        s = s[2...-1].strip
      end
      s
    end

    # --- format dispatch -----------------------------------------------------

    private def parse_file(path : String, content : String) : Array(TfResource)
      if path.ends_with?(".tf.json")
        parse_json(content)
      else
        parse_hcl(content)
      end
    end

    # --- Terraform JSON ------------------------------------------------------

    private def parse_json(content : String) : Array(TfResource)
      results = [] of TfResource
      root = JSON.parse(content).as_h?
      return results unless root
      resource_node = root["resource"]?
      return results unless resource_node

      each_json_resource(resource_node) do |type, name, attrs_node|
        results << TfResource.new(type, name, extract_json_attrs(attrs_node))
      end
      results
    end

    # `resource` is `{ type => { name => attrs } }`, and Terraform JSON also
    # allows the container (or an individual block) to be an array.
    private def each_json_resource(node : JSON::Any, &block : String, String, JSON::Any ->)
      if arr = node.as_a?
        arr.each { |el| each_json_resource(el, &block) }
        return
      end

      types = node.as_h?
      return unless types
      types.each do |type, names_node|
        names = names_node.as_h?
        next unless names
        names.each do |name, attrs_node|
          if blocks = attrs_node.as_a?
            blocks.each { |b| yield type, name, b }
          else
            yield type, name, attrs_node
          end
        end
      end
    end

    private def extract_json_attrs(node : JSON::Any) : Hash(String, String)
      attrs = {} of String => String
      h = node.as_h?
      return attrs unless h
      TARGET_ATTRS.each do |key|
        if v = h[key]?.try(&.as_s?)
          attrs[key] = v
        end
      end
      attrs
    end

    # --- HCL scanner ---------------------------------------------------------
    #
    # A small, allocation-light HCL reader. It is string-, comment- and
    # heredoc-aware so that brace-heavy earlier blocks (IAM policy heredocs,
    # `jsonencode({...})`) can't desync the block matcher and swallow later
    # resources. It only understands as much HCL as endpoint extraction needs.

    private def parse_hcl(content : String) : Array(TfResource)
      results = [] of TfResource
      chars = content.chars
      len = chars.size
      i = 0

      while i < len
        i = skip_ws_comments(chars, i, len)
        break if i >= len

        keyword, i = read_ident(chars, i, len)
        if keyword.empty?
          i += 1 # not an identifier char; advance to avoid stalling
          next
        end

        if keyword == "resource"
          i = skip_ws_comments(chars, i, len)
          if i < len && chars[i] == '"'
            type, i = read_string(chars, i, len)
            i = skip_ws_comments(chars, i, len)
            name = ""
            if i < len && chars[i] == '"'
              name, i = read_string(chars, i, len)
              i = skip_ws_comments(chars, i, len)
            end
            if i < len && chars[i] == '{'
              body, i = read_block(chars, i, len)
              results << TfResource.new(type, name, parse_body_attrs(body)) if target_type?(type)
            end
          end
        else
          # Any other top-level block (terraform/provider/variable/data/module/
          # output/locals). Skip its labels and body so scanning resumes cleanly.
          i = skip_labels_and_block(chars, i, len)
        end
      end

      results
    end

    private def target_type?(type : String) : Bool
      type == RESOURCE_TYPE_V2 || type == RESOURCE_TYPE_REST_R || type == RESOURCE_TYPE_REST_M
    end

    private def parse_body_attrs(chars : Array(Char)) : Hash(String, String)
      attrs = {} of String => String
      len = chars.size
      i = 0

      while i < len
        i = skip_ws_comments(chars, i, len)
        break if i >= len

        key, i = read_ident(chars, i, len)
        if key.empty?
          i += 1
          next
        end

        i = skip_ws_comments(chars, i, len)
        break if i >= len
        c = chars[i]

        if c == '='
          i += 1
          i = skip_ws_comments(chars, i, len)
          break if i >= len
          vc = chars[i]
          if vc == '"'
            val, i = read_string(chars, i, len)
            attrs[key] = val if TARGET_ATTRS.includes?(key)
          elsif vc == '{'
            _, i = read_block(chars, i, len)
          elsif vc == '['
            i = skip_bracket(chars, i, len)
          elsif vc == '<' && i + 1 < len && chars[i + 1] == '<'
            i = skip_heredoc(chars, i, len)
          else
            # A bare (unquoted) value is a reference/expression. Only the graph
            # attributes are meaningful as references; a bare route_key /
            # path_part / http_method is a computed value and is intentionally
            # not captured.
            val, i = read_expression(chars, i, len)
            attrs[key] = val.strip if REF_ATTRS.includes?(key)
          end
        elsif c == '{'
          _, i = read_block(chars, i, len) # nested block: `settings { ... }`
        elsif c == '"'
          i = skip_labels_and_block(chars, i, len) # labelled block: `dynamic "x" { }`
        else
          i += 1
        end
      end

      attrs
    end

    private def read_ident(chars : Array(Char), i : Int32, len : Int32) : Tuple(String, Int32)
      start = i
      while i < len && ident_char?(chars[i])
        i += 1
      end
      {slice(chars, start, i), i}
    end

    private def ident_char?(c : Char) : Bool
      c.ascii_alphanumeric? || c == '_'
    end

    private def skip_ws_comments(chars : Array(Char), i : Int32, len : Int32) : Int32
      loop do
        while i < len && chars[i].whitespace?
          i += 1
        end
        break if i >= len
        c = chars[i]
        if c == '#'
          i += 1
          i = advance_to_eol(chars, i, len)
        elsif c == '/' && i + 1 < len && chars[i + 1] == '/'
          i += 2
          i = advance_to_eol(chars, i, len)
        elsif c == '/' && i + 1 < len && chars[i + 1] == '*'
          i += 2
          while i + 1 < len && !(chars[i] == '*' && chars[i + 1] == '/')
            i += 1
          end
          i = i + 2 < len ? i + 2 : len
        else
          break
        end
      end
      i
    end

    # `i` points at the opening quote. Returns the raw string content (escapes
    # are left as-is — the target attributes never rely on them) and the index
    # just past the closing quote. `${...}` / `%{...}` interpolations are
    # consumed whole (including nested quotes and braces) so the terminating
    # quote is found correctly.
    private def read_string(chars : Array(Char), i : Int32, len : Int32) : Tuple(String, Int32)
      i += 1
      start = i
      interp = 0
      while i < len
        c = chars[i]
        if interp == 0
          if c == '\\'
            i += 2
          elsif c == '$' && i + 1 < len && chars[i + 1] == '{'
            interp = 1
            i += 2
          elsif c == '%' && i + 1 < len && chars[i + 1] == '{'
            interp = 1
            i += 2
          elsif c == '"'
            return {slice(chars, start, i), i + 1}
          else
            i += 1
          end
        else
          if c == '\\'
            i += 2
          elsif c == '"'
            _, i = read_string(chars, i, len)
          elsif c == '{'
            interp += 1
            i += 1
          elsif c == '}'
            interp -= 1
            i += 1
          else
            i += 1
          end
        end
      end
      {slice(chars, start, i), i}
    end

    # `i` points at the opening `{`. Returns the inner body (as chars) and the
    # index just past the matching `}`.
    private def read_block(chars : Array(Char), i : Int32, len : Int32) : Tuple(Array(Char), Int32)
      depth = 0
      body_start = i + 1
      while i < len
        c = chars[i]
        if c == '#'
          i += 1
          i = advance_to_eol(chars, i, len)
        elsif c == '/' && i + 1 < len && chars[i + 1] == '/'
          i += 2
          i = advance_to_eol(chars, i, len)
        elsif c == '/' && i + 1 < len && chars[i + 1] == '*'
          i += 2
          while i + 1 < len && !(chars[i] == '*' && chars[i + 1] == '/')
            i += 1
          end
          i = i + 2 < len ? i + 2 : len
        elsif c == '"'
          _, i = read_string(chars, i, len)
        elsif c == '<' && i + 1 < len && chars[i + 1] == '<'
          i = skip_heredoc(chars, i, len)
        elsif c == '{'
          depth += 1
          i += 1
        elsif c == '}'
          depth -= 1
          i += 1
          return {slice_chars(chars, body_start, i - 1), i} if depth == 0
        else
          i += 1
        end
      end
      {slice_chars(chars, body_start, len), i}
    end

    # `i` points at the first `<` of `<<` / `<<-`. Skips to just past the
    # terminator line.
    private def skip_heredoc(chars : Array(Char), i : Int32, len : Int32) : Int32
      j = i + 2
      j += 1 if j < len && chars[j] == '-'
      tag_start = j
      while j < len && ident_char?(chars[j])
        j += 1
      end
      tag = slice(chars, tag_start, j)
      return i + 2 if tag.empty?

      # skip the remainder of the opening line
      while j < len && chars[j] != '\n'
        j += 1
      end
      j += 1 if j < len

      while j < len
        line_start = j
        while j < len && chars[j] != '\n'
          j += 1
        end
        line = slice(chars, line_start, j)
        j += 1 if j < len
        return j if line.strip == tag
      end
      j
    end

    # `i` points at the opening `[`. Returns the index just past the matching `]`.
    # Strings, comments and heredocs are consumed whole so bracket chars inside
    # them can't desync the depth counter.
    private def skip_bracket(chars : Array(Char), i : Int32, len : Int32) : Int32
      depth = 0
      while i < len
        c = chars[i]
        if c == '"'
          _, i = read_string(chars, i, len)
        elsif c == '#'
          i += 1
          i = advance_to_eol(chars, i, len)
        elsif c == '/' && i + 1 < len && chars[i + 1] == '/'
          i += 2
          i = advance_to_eol(chars, i, len)
        elsif c == '/' && i + 1 < len && chars[i + 1] == '*'
          i += 2
          while i + 1 < len && !(chars[i] == '*' && chars[i + 1] == '/')
            i += 1
          end
          i = i + 2 < len ? i + 2 : len
        elsif c == '<' && i + 1 < len && chars[i + 1] == '<'
          i = skip_heredoc(chars, i, len)
        elsif c == '['
          depth += 1
          i += 1
        elsif c == ']'
          depth -= 1
          i += 1
          return i if depth == 0
        else
          i += 1
        end
      end
      i
    end

    # Read an unquoted attribute value (a reference or expression) up to the end
    # of the line, stopping before a trailing line comment.
    private def read_expression(chars : Array(Char), i : Int32, len : Int32) : Tuple(String, Int32)
      start = i
      while i < len && chars[i] != '\n'
        break if chars[i] == '#'
        break if chars[i] == '/' && i + 1 < len && chars[i + 1] == '/'
        i += 1
      end
      {slice(chars, start, i), i}
    end

    # Skip zero or more string labels followed by a `{ ... }` block.
    private def skip_labels_and_block(chars : Array(Char), i : Int32, len : Int32) : Int32
      loop do
        i = skip_ws_comments(chars, i, len)
        break if i >= len
        c = chars[i]
        if c == '"'
          _, i = read_string(chars, i, len)
        elsif c == '{'
          _, i = read_block(chars, i, len)
          break
        elsif ident_char?(c)
          _, i = read_ident(chars, i, len)
        else
          break
        end
      end
      i
    end

    private def advance_to_eol(chars : Array(Char), i : Int32, len : Int32) : Int32
      while i < len && chars[i] != '\n'
        i += 1
      end
      i
    end

    private def slice(chars : Array(Char), a : Int32, b : Int32) : String
      b = len_clamp(chars, b)
      return "" if a >= b
      String.build { |io| (a...b).each { |k| io << chars[k] } }
    end

    private def slice_chars(chars : Array(Char), a : Int32, b : Int32) : Array(Char)
      b = len_clamp(chars, b)
      return [] of Char if a >= b
      chars[a...b]
    end

    private def len_clamp(chars : Array(Char), b : Int32) : Int32
      b > chars.size ? chars.size : b
    end
  end
end
