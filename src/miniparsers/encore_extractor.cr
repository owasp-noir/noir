require "../ext/tree_sitter/tree_sitter"
require "../utils/top_level_split"
require "./js_route_extractor"

module Noir
  # Encore (https://encore.dev) API declarations.
  #
  # Go: a `//encore:api [public|private|auth] [raw] [method=A,B] [path=/p]`
  # directive in the doc comment of a function or service method.
  #
  # TypeScript: `export const name = api({...}, handler)` and its
  # `api.raw` / `api.streamIn` / `api.streamOut` / `api.streamInOut` /
  # `api.static` variants, from `encore.dev/api`.
  module EncoreExtractor
    extend self

    # `params` holds one type string per declared parameter (receiver
    # excluded), so `func F(ctx context.Context, id int, p *Req)` gives
    # `["context.Context", "int", "*Req"]`.
    record GoApi, name : String, options : Array(String), fields : Hash(String, String),
      params : Array(String), line : Int32

    # A request-struct field: Go field name and its raw tag text.
    record GoField, name : String, tag : String

    # `kind` is `api`, `raw`, `streamIn`, `streamOut`, `streamInOut` or `static`.
    # `config` is the first argument's object text; `fields` are the request
    # type's fields (from the generic argument or the handler's parameter
    # annotation), when the type is inline or declared in the same file.
    record TsApi, name : String, kind : String, config : String, fields : Array(TsField), line : Int32

    # A request field: name and its TypeScript type text.
    record TsField, name : String, type : String

    GO_DIRECTIVE = "//encore:api"

    # Encore path syntax: `:name` and `*rest` params, plus the `!rest`
    # fallback, reported as `*rest`. Returns the URL and its param names.
    def route(path : String) : Tuple(String, Array(String))
      url = path.gsub("/!", "/*")
      {url, url.split('/').compact_map { |seg| seg[1..] if seg.starts_with?(':') || seg.starts_with?('*') }}
    end

    # Parses `source` once, returning its API declarations and every
    # `type X struct {...}` (request types may live in another file of the
    # package, so callers merge the struct tables per directory).
    def extract_go(source : String) : Tuple(Array(GoApi), Hash(String, Array(GoField)))
      apis = [] of GoApi
      structs = Hash(String, Array(GoField)).new
      TreeSitter.parse_go(source) do |root|
        directive : String? = nil
        directive_end = -2
        TreeSitter.each_named_child(root) do |node|
          case TreeSitter.node_type(node)
          when "comment"
            text = TreeSitter.node_text(node, source)
            # A blank line ends a doc comment group.
            directive = nil if TreeSitter.node_start_row(node) > directive_end + 1
            directive = text if text.starts_with?(GO_DIRECTIVE) && (text.size == GO_DIRECTIVE.size || text[GO_DIRECTIVE.size].whitespace?)
            directive_end = TreeSitter.node_end_row(node)
          when "function_declaration", "method_declaration"
            if (dir = directive) && TreeSitter.node_start_row(node) == directive_end + 1
              if api = go_api(node, dir, source)
                apis << api
              end
            end
            directive = nil
          when "type_declaration"
            collect_structs(node, source, structs)
            directive = nil
          else
            directive = nil
          end
        end
      end
      {apis, structs}
    end

    private def go_api(node : LibTreeSitter::TSNode, directive : String, source : String) : GoApi?
      name_node = TreeSitter.field(node, "name") || return
      options = [] of String
      fields = Hash(String, String).new
      directive[GO_DIRECTIVE.size..].split.each do |token|
        if eq = token.index('=')
          fields[token[0...eq]] = token[(eq + 1)..]
        else
          options << token
        end
      end

      params = [] of String
      if list = TreeSitter.field(node, "parameters")
        TreeSitter.each_named_child(list) do |decl|
          next unless TreeSitter.node_type(decl) == "parameter_declaration"
          type = TreeSitter.field(decl, "type").try { |t| TreeSitter.node_text(t, source) } || ""
          names = 0
          TreeSitter.each_named_child(decl) { |c| names += 1 if TreeSitter.node_type(c) == "identifier" }
          {names, 1}.max.times { params << type }
        end
      end

      GoApi.new(TreeSitter.node_text(name_node, source), options, fields, params, TreeSitter.node_start_row(node) + 1)
    end

    private def collect_structs(decl : LibTreeSitter::TSNode, source : String, structs : Hash(String, Array(GoField)))
      TreeSitter.each_named_child(decl) do |spec|
        next unless TreeSitter.node_type(spec) == "type_spec"
        name_node = TreeSitter.field(spec, "name") || next
        type_node = TreeSitter.field(spec, "type") || next
        next unless TreeSitter.node_type(type_node) == "struct_type"

        fields = [] of GoField
        TreeSitter.each_named_child(type_node) do |list|
          next unless TreeSitter.node_type(list) == "field_declaration_list"
          TreeSitter.each_named_child(list) do |field|
            next unless TreeSitter.node_type(field) == "field_declaration"
            # `json:"x"` raw, or `"json:\"x\""` interpreted.
            tag = TreeSitter.field(field, "tag").try { |t| TreeSitter.node_text(t, source)[1..-2].gsub("\\\"", '"') } || ""
            TreeSitter.each_named_child(field) do |c|
              fields << GoField.new(TreeSitter.node_text(c, source), tag) if TreeSitter.node_type(c) == "field_identifier"
            end
          end
        end
        structs[TreeSitter.node_text(name_node, source)] ||= fields
      end
    end

    # One level of generic nesting: `api<Req, Promise<Res>>(...)`.
    TS_API = /\bexport\s+const\s+([A-Za-z_$][\w$]*)(?:\s*:[^=;\n]+)?\s*=\s*api(?:\.(raw|streamIn|streamOut|streamInOut|static))?\s*(?:<((?:[^<>]|<[^<>]*>)*)>)?\s*\(/

    def extract_ts(content : String) : Array(TsApi)
      return [] of TsApi unless content.includes?("encore.dev")

      code = JSRouteExtractor.strip_js_comments(content)
      apis = [] of TsApi
      code.scan(TS_API) do |m|
        open = m.end(0) - 1
        close = JSRouteExtractor.find_matching_paren(code, open) || next
        args = TopLevelSplit.split(code[(open + 1)...close], ',', TopLevelSplit::Rules::JS)
        config = args[0]? || next
        next unless config.starts_with?('{')

        request = m[3]?.try { |g| TopLevelSplit.split(g, ',', TYPE_RULES).first? } || handler_request_type(args[1]?)
        fields = request ? request_fields(request, code) : [] of TsField
        apis << TsApi.new(m[1], m[2]? || "api", config, fields, JSRouteExtractor.line_for_char_pos(code, m.begin(0)))
      end
      apis
    end

    # `{ expose: true, method: "GET" }` → `"true"` for `expose`, `"\"GET\""` for `method`.
    def ts_config_value(config : String, key : String) : String?
      body = config.strip.lchop('{').rchop('}')
      TopLevelSplit.split(body, ',', TopLevelSplit::Rules::JS).each do |entry|
        colon = entry.index(':') || next
        return entry[(colon + 1)..].strip if entry[0...colon].strip.strip("\"'") == key
      end
      nil
    end

    # Quoted strings in `value`: `"GET"` → `["GET"]`, `["GET", "POST"]` → both.
    def ts_strings(value : String) : Array(String)
      value.scan(/["'`]([^"'`]*)["'`]/).map(&.[1])
    end

    # Fields of a request type: an inline `{ a: string; b?: Header<"X"> }`
    # literal, or an `interface X {}` / `type X = {}` declared in the file.
    private def request_fields(type : String, code : String) : Array(TsField)
      type = type.strip
      body = if type.starts_with?('{')
               type
             elsif type.matches?(/\A[A-Za-z_$][\w$]*\z/)
               type_body(code, type)
             end
      return [] of TsField unless body

      TopLevelSplit.split(body.strip.lchop('{').rchop('}'), ';', TYPE_RULES).flat_map do |part|
        TopLevelSplit.split(part, '\n', TYPE_RULES)
      end.flat_map do |part|
        TopLevelSplit.split(part, ',', TYPE_RULES)
      end.compact_map do |entry|
        m = entry.match(/\A(?:readonly\s+)?["']?([A-Za-z_$][\w$-]*)["']?\??\s*:\s*(.+)\z/m) || next
        TsField.new(m[1], m[2].strip)
      end
    end

    TYPE_RULES = TopLevelSplit::Rules.new(
      nest: TopLevelSplit::Nest::Paren | TopLevelSplit::Nest::Bracket | TopLevelSplit::Nest::Brace | TopLevelSplit::Nest::Angle,
      quotes: "\"'`",
      empties: TopLevelSplit::Empties::DropAll,
      per_kind: true,
    )

    private def type_body(code : String, name : String) : String?
      m = code.match(/\b(?:interface\s+#{Regex.escape(name)}\b[^{]*|type\s+#{Regex.escape(name)}\s*=\s*)\{/) || return
      open = m.end(0) - 1
      close = JSRouteExtractor.find_matching_brace(code, open) || return
      code[open..close]
    end

    # The first handler parameter's annotation: `({ id }: { id: number })`
    # or `(p: Params)` → `{ id: number }` / `Params`.
    private def handler_request_type(handler : String?) : String?
      handler = handler.try(&.lstrip.lchop("async").lstrip) || return
      handler = handler.sub(/\Afunction\b[^(]*/, "")
      return unless handler.starts_with?('(')
      close = JSRouteExtractor.find_matching_paren(handler, 0) || return
      first = TopLevelSplit.split(handler[1...close], ',', TopLevelSplit::Rules::JS).first? || return
      colon = top_level_colon(first) || return
      first[(colon + 1)..].strip
    end

    # Index of the first `:` outside a destructuring `{...}` / `[...]`.
    private def top_level_colon(text : String) : Int32?
      depth = 0
      text.each_char_with_index do |c, i|
        case c
        when '{', '[' then depth += 1
        when '}', ']' then depth -= 1
        when ':'      then return i if depth == 0
        end
      end
      nil
    end
  end
end
