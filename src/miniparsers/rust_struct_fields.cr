require "../ext/tree_sitter/tree_sitter"

# Wire names of a Rust source's named-field structs, the way serde and
# Rocket's `FromForm` read them: a container `#[serde(rename_all = "…")]`
# recases every field, a field's `#[serde(rename = "…")]` or Rocket
# `#[field(name = "…")]` replaces its name, and `skip` / `skip_deserializing`
# / `flatten` fields are left out (a flattened field's own name is never on
# the wire). Tuple and unit structs have no named fields and are omitted.
#
# No file I/O: callers hand over source text.
module Noir::RustStructFields
  RENAME_ALL_RE = /\bserde\s*\((?:[^()]|\([^()]*\))*\brename_all\s*=\s*"([^"]+)"/
  RENAME_RE     = /\bserde\s*\((?:[^()]|\([^()]*\))*\brename\s*=\s*"([^"]+)"/
  FORM_NAME_RE  = /\bfield\s*\((?:[^()]|\([^()]*\))*\bname\s*=\s*(?:uncased\s*\(\s*)?"([^"]+)"/
  OMIT_RE       = /\bserde\s*\((?:[^()]|\([^()]*\))*\b(?:skip|skip_deserializing|flatten)\b(?!\s*=)/

  # `{struct_name => [wire field names]}`; first definition wins.
  def self.parse(source : String) : Hash(String, Array(String))
    structs = {} of String => Array(String)
    Noir::TreeSitter.parse_rust(source) do |root|
      collect(root, source, structs, 0)
    end
    structs
  end

  private def self.collect(container : LibTreeSitter::TSNode, source : String,
                           structs : Hash(String, Array(String)), depth : Int32)
    return if depth > 16
    attrs = [] of String
    Noir::TreeSitter.each_named_child(container) do |child|
      case Noir::TreeSitter.node_type(child)
      when "attribute_item"
        attrs << Noir::TreeSitter.node_text(child, source)
      when "line_comment", "block_comment"
        next
      when "struct_item"
        if (name = Noir::TreeSitter.field(child, "name")) && (fields = fields_of(child, attrs, source))
          structs[Noir::TreeSitter.node_text(name, source)] ||= fields
        end
        attrs.clear
      when "mod_item"
        if body = Noir::TreeSitter.field(child, "body")
          collect(body, source, structs, depth + 1)
        end
        attrs.clear
      else
        attrs.clear
      end
    end
  end

  private def self.fields_of(struct_node : LibTreeSitter::TSNode, container_attrs : Array(String),
                             source : String) : Array(String)?
    body = Noir::TreeSitter.field(struct_node, "body")
    return unless body && Noir::TreeSitter.node_type(body) == "field_declaration_list"
    rename_all = container_attrs.compact_map { |a| a.match(RENAME_ALL_RE).try(&.[1]) }.first?

    fields = [] of String
    attrs = [] of String
    Noir::TreeSitter.each_named_child(body) do |child|
      case Noir::TreeSitter.node_type(child)
      when "attribute_item"
        attrs << Noir::TreeSitter.node_text(child, source)
      when "field_declaration"
        if (name_node = Noir::TreeSitter.field(child, "name")) && attrs.none?(&.matches?(OMIT_RE))
          explicit = attrs.compact_map { |a| (a.match(RENAME_RE) || a.match(FORM_NAME_RE)).try(&.[1]) }.first?
          fields << (explicit || recase(Noir::TreeSitter.node_text(name_node, source).lchop("r#"), rename_all))
        end
        attrs.clear
      end
    end
    fields
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
