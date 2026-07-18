require "../ext/tree_sitter/tree_sitter"

module Noir
  # Extracts declarative object-literal configs out of JS/TS sources.
  #
  # Several frameworks describe their HTTP surface as a plain object
  # rather than as route calls — Payload CMS collections
  # (`{ slug, fields }`) and Strapi route files (`{ routes: [...] }`)
  # among them. Both are read the same way: find the object literals
  # that carry a known set of keys and decode them into Crystal data.
  #
  # The search is a depth-first sweep for *any* `object` node holding the
  # required keys, deliberately not a match on the `export const X = {…}`
  # declaration spine. That makes it indifferent to how the object is
  # declared, which in the wild means all of:
  #
  # ```
  # export const Posts: CollectionConfig = { slug: 'posts', fields: [] }
  # export const Posts = { slug: 'posts', fields: [] } satisfies CollectionConfig
  # export default buildConfig({ collections: [{ slug: 'posts', fields: [] }] })
  # module.exports = { slug: 'posts', fields: [] }
  # ```
  #
  # TypeScript is parsed with the vendored JavaScript grammar (no
  # TypeScript grammar is vendored — see `tree_sitter.cr`) after two
  # narrow annotation strips, below.
  module JSObjectConfigExtractor
    extend self

    # `export const Posts: CollectionConfig = {` would otherwise parse
    # with the *type* as the variable name. Line-preserving so the
    # reported line still matches the original source.
    DECLARATION_ANNOTATION = /(\b(?:export\s+)?(?:const|let|var)\s+[A-Za-z_$][\w$]*)\s*:\s*[^=\n]+=/

    # `} satisfies CollectionConfig` is Payload's modern idiom and the JS
    # grammar has no `satisfies` operator.
    SATISFIES_ASSERTION = /\bsatisfies\s+[A-Za-z_$][\w$.]*(?:<[^>\n]*>)?/

    # Deliberately NOT reusing `JSCalleeExtractor`'s normalizer: its
    # function-parameter rules cannot tell a signature from an object
    # literal, so `{ path: '/x', handler: 'y' }` is rewritten to
    # `{ path, handler }` and every value is lost. Only the two strips
    # above are safe on declarative config.
    private def normalize(source : String) : String
      source.gsub(DECLARATION_ANNOTATION, "\\1 =").gsub(SATISFIES_ASSERTION, "")
    end

    alias ConfigValue = String | Float64 | Bool | Array(ConfigValue) | Hash(String, ConfigValue)?

    # Guards against pathological nesting in generated configs.
    MAX_VALUE_DEPTH = 12

    struct ConfigObject
      getter data : Hash(String, ConfigValue)
      # 1-based, for `PathInfo`.
      getter line : Int32

      def initialize(@data : Hash(String, ConfigValue), @line : Int32)
      end

      def [](key : String) : ConfigValue
        @data[key]?
      end

      def string(key : String) : String?
        value = @data[key]?
        value.is_a?(String) ? value : nil
      end

      def bool(key : String) : Bool?
        value = @data[key]?
        value.is_a?(Bool) ? value : nil
      end

      def array(key : String) : Array(ConfigValue)?
        value = @data[key]?
        value.is_a?(Array(ConfigValue)) ? value : nil
      end

      def hash(key : String) : Hash(String, ConfigValue)?
        value = @data[key]?
        value.is_a?(Hash(String, ConfigValue)) ? value : nil
      end

      def truthy?(key : String) : Bool
        value = @data[key]?
        case value
        when Bool then value
        when Nil  then false
        else           true
        end
      end
    end

    # Returns every object literal in `source` carrying all of
    # `required_keys`. Once an object matches, its own subtree is not
    # searched again — otherwise a nested config would surface twice.
    def extract(source : String, required_keys : Array(String)) : Array(ConfigObject)
      found = [] of ConfigObject
      return found if source.empty? || required_keys.empty?

      normalized = normalize(source)
      Noir::TreeSitter.parse_javascript(normalized) do |root|
        walk(root, normalized, required_keys, found, 0)
      end
      found
    end

    private def walk(node : LibTreeSitter::TSNode, source : String,
                     required_keys : Array(String), found : Array(ConfigObject), depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "object"
        data = decode_object(node, source, 0)
        if required_keys.all? { |key| data.has_key?(key) }
          found << ConfigObject.new(data, Noir::TreeSitter.node_start_row(node) + 1)
          # Matched objects are terminal: descending would re-report the
          # same config from an inner object that happens to repeat the
          # required keys.
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, required_keys, found, depth + 1)
      end
    end

    private def decode_object(node : LibTreeSitter::TSNode, source : String, depth : Int32) : Hash(String, ConfigValue)
      data = Hash(String, ConfigValue).new
      return data if depth > MAX_VALUE_DEPTH

      Noir::TreeSitter.each_named_child(node) do |pair|
        next unless Noir::TreeSitter.node_type(pair) == "pair"
        key, value = pair_key_value(pair, source)
        next if key.empty?
        data[key] = value ? decode_value(value, source, depth + 1) : nil
      end

      data
    end

    private def pair_key_value(pair : LibTreeSitter::TSNode, source : String) : Tuple(String, LibTreeSitter::TSNode?)
      key = ""
      value : LibTreeSitter::TSNode? = nil

      Noir::TreeSitter.each_named_child(pair) do |child|
        case Noir::TreeSitter.node_type(child)
        when "property_identifier", "identifier"
          if key.empty?
            key = Noir::TreeSitter.node_text(child, source)
          else
            value = child if value.nil?
          end
        when "string"
          if key.empty?
            key = decode_string(child, source)
          else
            value = child if value.nil?
          end
        else
          value = child if value.nil?
        end
      end

      {key, value}
    end

    private def decode_value(node : LibTreeSitter::TSNode, source : String, depth : Int32) : ConfigValue
      return if depth > MAX_VALUE_DEPTH

      case Noir::TreeSitter.node_type(node)
      when "string", "template_string"
        decode_string(node, source)
      when "number"
        Noir::TreeSitter.node_text(node, source).to_f?
      when "true"
        true
      when "false"
        false
      when "null", "undefined"
        nil
      when "array"
        items = [] of ConfigValue
        Noir::TreeSitter.each_named_child(node) do |elem|
          items << decode_value(elem, source, depth + 1)
        end
        items
      when "object"
        decode_object(node, source, depth)
      end
      # Anything else — arrow functions, identifiers, calls, spreads —
      # carries no value we can resolve statically, so the case falls
      # through to nil. The key is still recorded, so `has_key?` sees it.
    end

    # tree-sitter-javascript exposes string contents as `string_fragment`
    # children; joining them keeps simple literals exact without choking
    # on escapes or interpolation.
    private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          type = Noir::TreeSitter.node_type(child)
          io << Noir::TreeSitter.node_text(child, source) if type == "string_fragment" || type == "template_string_fragment"
        end
      end
      return buf unless buf.empty?

      raw = Noir::TreeSitter.node_text(node, source)
      if raw.size >= 2 && (raw[0] == '\'' || raw[0] == '"' || raw[0] == '`') && raw[0] == raw[-1]
        raw[1..-2]
      else
        raw
      end
    end
  end
end
