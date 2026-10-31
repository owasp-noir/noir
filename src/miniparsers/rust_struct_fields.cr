require "../ext/tree_sitter/tree_sitter"

# Wire names of a Rust source's named-field structs, the way serde and
# Rocket's `FromForm` read them (deserr's `#[deserr(rename_all = camelCase)]`
# is read like serde's): a container `#[serde(rename_all = "…")]`
# recases every field, a field's `#[serde(rename = "…")]` or Rocket
# `#[field(name = "…")]` replaces its name, and `skip` / `skip_deserializing`
# fields are left out. A `flatten` field's own name is never on the wire:
# its type's fields are, so its type text is kept in `Shape#flattened` for
# the caller to resolve. Tuple and unit structs have no named fields and are
# omitted, and so are structs of inline `mod`s: a bare name in a file means
# its top-level item, never `mod legacy { struct X }`.
#
# No file I/O: callers hand over source text.
module Noir::RustStructFields
  record Shape, fields : Array(String), flattened : Array(String)

  RENAME_ALL_RE = /\b(?:serde|deserr)\s*\((?:[^()]|\([^()]*\))*\brename_all\s*=\s*"?([^",)\s]+)"?/
  RENAME_RE     = /\b(?:serde|deserr)\s*\((?:[^()]|\([^()]*\))*\brename\s*=\s*"([^"]+)"/
  FORM_NAME_RE  = /\bfield\s*\((?:[^()]|\([^()]*\))*\bname\s*=\s*(?:uncased\s*\(\s*)?"([^"]+)"/
  OMIT_RE       = /\b(?:serde|deserr)\s*\((?:[^()]|\([^()]*\))*\b(?:skip|skip_deserializing)\b(?!\s*=)/
  FLATTEN_RE    = /\b(?:serde|deserr)\s*\((?:[^()]|\([^()]*\))*\bflatten\b(?!\s*=)/

  # `{struct_name => Shape}` of the top-level structs; first definition wins.
  def self.parse(source : String) : Hash(String, Shape)
    structs = {} of String => Shape
    Noir::TreeSitter.parse_rust(source) do |root|
      collect(root, source, structs)
    end
    structs
  end

  private def self.collect(container : LibTreeSitter::TSNode, source : String,
                           structs : Hash(String, Shape))
    attrs = [] of String
    Noir::TreeSitter.each_named_child(container) do |child|
      case Noir::TreeSitter.node_type(child)
      when "attribute_item"
        attrs << Noir::TreeSitter.node_text(child, source)
      when "line_comment", "block_comment"
        next
      when "struct_item"
        if (name = Noir::TreeSitter.field(child, "name")) && (shape = fields_of(child, attrs, source))
          structs[Noir::TreeSitter.node_text(name, source)] ||= shape
        end
        attrs.clear
      else
        attrs.clear
      end
    end
  end

  private def self.fields_of(struct_node : LibTreeSitter::TSNode, container_attrs : Array(String),
                             source : String) : Shape?
    body = Noir::TreeSitter.field(struct_node, "body")
    return unless body && Noir::TreeSitter.node_type(body) == "field_declaration_list"
    rename_all = container_attrs.compact_map { |a| a.match(RENAME_ALL_RE).try(&.[1]) }.first?

    fields = [] of String
    flattened = [] of String
    attrs = [] of String
    Noir::TreeSitter.each_named_child(body) do |child|
      case Noir::TreeSitter.node_type(child)
      when "attribute_item"
        attrs << Noir::TreeSitter.node_text(child, source)
      when "field_declaration"
        if attrs.any?(&.matches?(FLATTEN_RE))
          if attrs.none?(&.matches?(OMIT_RE)) && (type = Noir::TreeSitter.field(child, "type"))
            flattened << Noir::TreeSitter.node_text(type, source)
          end
        elsif (name_node = Noir::TreeSitter.field(child, "name")) && attrs.none?(&.matches?(OMIT_RE))
          explicit = attrs.compact_map { |a| (a.match(RENAME_RE) || a.match(FORM_NAME_RE)).try(&.[1]) }.first?
          fields << (explicit || recase(Noir::TreeSitter.node_text(name_node, source).lchop("r#"), rename_all))
        end
        attrs.clear
      end
    end
    Shape.new(fields, flattened)
  end

  # serde's `rename_all` rules applied to a snake_case field name.
  def self.recase(name : String, rule : String?) : String
    words = name.split('_').reject(&.empty?)
    return name if words.empty?
    case rule
    when "lowercase"            then name.downcase
    when "UPPERCASE"            then name.upcase
    when "camelCase"            then words[0].downcase + words[1..].map(&.capitalize).join
    when "PascalCase"           then words.map(&.capitalize).join
    when "SCREAMING_SNAKE_CASE" then name.upcase
    when "kebab-case"           then words.join('-')
    when "SCREAMING-KEBAB-CASE" then words.join('-').upcase
    else                             name
    end
  end
end
