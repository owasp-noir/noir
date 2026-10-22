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

    # One parsed `.go` file. Request types may live in another file of the
    # package, so callers merge `structs` per directory.
    record GoFile, package : String?, apis : Array(GoApi), structs : Hash(String, Array(GoField))

    # `kind` is `api`, `raw`, `streamIn`, `streamOut`, `streamInOut` or `static`;
    # `config` maps the first argument's keys to their value text. `fields`
    # are the request type's fields when it is inline or declared in the
    # file; a named type imported from a relative module is left to the
    # caller as `request_import` (`{declared name, specifier}`).
    record TsApi, name : String, kind : String, config : Hash(String, String),
      fields : Array(TsField), request_import : Tuple(String, String)?, line : Int32

    # A request field: name and its TypeScript type text.
    record TsField, name : String, type : String

    GO_DIRECTIVE = "//encore:api"

    # Encore path syntax: `:name` and `*rest` params, plus the `!rest`
    # fallback, reported as `*rest`. Returns the URL and its param names.
    def route(path : String) : Tuple(String, Array(String))
      url = path.gsub("/!", "/*")
      {url, url.split('/').compact_map { |seg| seg[1..] if seg.starts_with?(':') || seg.starts_with?('*') }}
    end

    def extract_go(source : String) : GoFile
      package = nil
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
          when "package_clause"
            package = TreeSitter.first_named_child(node).try { |n| TreeSitter.node_text(n, source) }
            directive = nil
          else
            directive = nil
          end
        end
      end
      GoFile.new(package, apis, structs)
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

    # ponytail: Huma and go_route_extractor_ts/gf each carry their own
    # struct-field walk; fold the three into one Go helper when a fourth appears.
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

    # The generic group recurses for nested `<...>` and steps over `=>`.
    TS_API     = /\bexport\s+const\s+([A-Za-z_$][\w$]*)(?:\s*:[^=;\n]+)?\s*=\s*api(?:\.(raw|streamIn|streamOut|streamInOut|static))?\s*(?<generic><(?:=>|[^<>]|(?&generic))*>)?\s*\(/
    TS_TYPE    = /\b(?:interface\s+([A-Za-z_$][\w$]*)\b[^{;]*|type\s+([A-Za-z_$][\w$]*)\s*=\s*)\{/
    TS_IMPORT  = /\bimport\s+(?:type\s+)?\{([^}]*)\}\s*from\s*["'](\.{1,2}\/[^"']+)["']/
    FIELD_HEAD = /\A(?:readonly\s+)?["']?([A-Za-z_$][\w$-]*)["']?\??\s*:\s*/
    IDENTIFIER = /\A[A-Za-z_$][\w$]*\z/
    TYPE_RULES = TopLevelSplit::Rules.new(
      nest: TopLevelSplit::Nest::Paren | TopLevelSplit::Nest::Bracket | TopLevelSplit::Nest::Brace | TopLevelSplit::Nest::Angle,
      quotes: "\"'`",
      empties: TopLevelSplit::Empties::DropAll,
      per_kind: true,
    )
    JS_RULES = TopLevelSplit::Rules::JS

    def extract_ts(content : String) : Array(TsApi)
      return [] of TsApi unless content.includes?("encore.dev")

      code = JSRouteExtractor.strip_js_comments(content)
      types = nil
      apis = [] of TsApi
      # Byte offsets throughout: char-indexed matching and slicing rescan
      # the file per api once it holds one non-ASCII char.
      offsets = JSRouteExtractor::ByteOffsets.new(code)
      code.scan(TS_API) do |m|
        open = m.byte_end(0) - 1
        close = JSLiteralScanner.find_matching_paren_at_byte(code, open) || next
        args = TopLevelSplit.split(code.byte_slice(open + 1, close - open - 1), ',', JS_RULES)
        config = args[0]? || next
        next unless config.starts_with?('{')

        kind = m[2]? || "api"
        handler = handler_params(args[1]?)
        request = m["generic"]?.try { |g| TopLevelSplit.split(g[1..-2], ',', TYPE_RULES).first? } ||
                  handler.first?.try { |p| TopLevelSplit.split(p, ':', JS_RULES)[1]? }
        # A stream's first type is its handshake only when the handler takes
        # `(handshake, stream)`; otherwise it is the message type.
        request = nil if kind.starts_with?("stream") && handler.size != 2

        fields = [] of TsField
        request_import = nil
        if request = request.try(&.strip)
          if request.starts_with?('{')
            fields = fields_of(request)
          elsif request.matches?(IDENTIFIER)
            types ||= type_bodies(code)
            if body = types[request]?
              fields = fields_of(body)
            else
              request_import = relative_import(code, request)
            end
          end
        end
        apis << TsApi.new(m[1], kind, object_entries(config), fields, request_import, offsets.line(m.byte_begin(0)))
      end
      apis
    end

    # Fields of the `interface`/`type` named `name` declared in `content`.
    def declared_fields(content : String, name : String) : Array(TsField)
      type_bodies(JSRouteExtractor.strip_js_comments(content))[name]?.try { |body| fields_of(body) } || [] of TsField
    end

    # Quoted strings in `value`: `"GET"` → `["GET"]`, `["GET", "POST"]` → both.
    def ts_strings(value : String) : Array(String)
      value.scan(/["'`]([^"'`]*)["'`]/).map(&.[1])
    end

    # Top-level generic arguments: `Header<number, "X-Count">` → `["number", "\"X-Count\""]`.
    def generic_args(type : String) : Array(String)
      open = type.index('<') || return [] of String
      TopLevelSplit.split(type[(open + 1)...(type.rindex('>') || type.size)], ',', TYPE_RULES)
    end

    # `{ expose: true, method: "GET" }` → `{"expose" => "true", "method" => "\"GET\""}`.
    private def object_entries(object : String) : Hash(String, String)
      TopLevelSplit.split(object.strip.lchop('{').rchop('}'), ',', JS_RULES).each_with_object({} of String => String) do |entry, hash|
        colon = entry.index(':') || next
        hash[entry[0...colon].strip.strip("\"'")] = entry[(colon + 1)..].strip
      end
    end

    # Every `interface X {...}` / `type X = {...}` body in `code`, by name.
    private def type_bodies(code : String) : Hash(String, String)
      bodies = Hash(String, String).new
      code.scan(TS_TYPE) do |m|
        open = m.byte_end(0) - 1
        close = JSLiteralScanner.find_matching_brace_at_byte(code, open) || next
        bodies[m[1]? || m[2]] ||= code.byte_slice(open, close - open + 1)
      end
      bodies
    end

    # Fields of a `{ a: string; b?: Header<"X"> }` body. Members end at `;`,
    # `,` or a newline; a piece that is not a member head (`| "closed"`)
    # continues the previous member's type.
    private def fields_of(body : String) : Array(TsField)
      members = [] of String
      TopLevelSplit.split(body.strip.lchop('{').rchop('}'), ';', TYPE_RULES).each do |part|
        TopLevelSplit.split(part, '\n', TYPE_RULES).each do |line|
          TopLevelSplit.split(line, ',', TYPE_RULES).each do |entry|
            if entry.matches?(FIELD_HEAD) || members.empty?
              members << entry
            else
              members[-1] += " #{entry}"
            end
          end
        end
      end
      members.compact_map do |member|
        m = member.match(FIELD_HEAD) || next
        type = member[m.end(0)..].strip
        TsField.new(m[1], type) unless type.empty?
      end
    end

    # `{declared name, "./specifier"}` for a name brought in by a relative
    # `import { Name } from "./x"` (or `import { Declared as Name }`).
    private def relative_import(code : String, name : String) : Tuple(String, String)?
      code.scan(TS_IMPORT) do |m|
        m[1].split(',').each do |spec|
          declared, _, local = spec.strip.lchop("type ").partition(/\s+as\s+/)
          return {declared, m[2]} if (local.presence || declared) == name
        end
      end
      nil
    end

    # Top-level parameters of an arrow or function handler:
    # `async ({ id }: { id: number }, stream) => ...` → `["{ id }: { id: number }", "stream"]`.
    private def handler_params(handler : String?) : Array(String)
      handler = handler.try(&.lstrip.lchop("async").lstrip.sub(/\Afunction\b[^(]*/, "")) || return [] of String
      return [handler.split(/\s*=>/, 2).first] if handler.matches?(/\A[A-Za-z_$][\w$]*\s*=>/)
      return [] of String unless handler.starts_with?('(')
      close = JSRouteExtractor.find_matching_paren(handler, 0) || return [] of String
      TopLevelSplit.split(handler[1...close], ',', JS_RULES)
    end
  end
end
