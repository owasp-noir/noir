require "../ext/tree_sitter/tree_sitter"

# What a Rust file's top-level items bring into scope, read from the tree:
#
#   use lemmy_api::{post::{create::create_post, save::save_post as save}};
#   pub use self::handlers::*;
#   #[path = "impl/real.rs"] mod real;
#
# gives `create_post => lemmy_api::post::create::create_post`,
# `save => lemmy_api::post::save::save_post`, the public glob
# `self::handlers`, the module `real` at `impl/real.rs`, and the file's own
# top-level fns. Only the top level is read: a `use` inside a fn or an
# inline `mod` is scoped to that block. Items under `#[cfg(test)]` are left
# out, and a name two `use`s bind to different paths is dropped as
# ambiguous (e.g. `#[cfg(feature = "a")]` / `#[cfg(not(feature = "a"))]`).
#
# No file I/O: callers hand over source text.
module Noir::RustUseImports
  class Imports
    # local name => full path as written
    getter names = {} of String => String
    getter globs = [] of String
    # The subset re-exported with `pub use`.
    getter pub_names = Set(String).new
    getter pub_globs = [] of String
    # Top-level `fn` name => 1-based line of the name.
    getter fns = {} of String => Int32
    # Declared `mod name;` / `mod name { }` names.
    getter mods = Set(String).new
    # `#[path = "…"] mod name;` => that path.
    getter mod_paths = {} of String => String
    getter ambiguous = Set(String).new
  end

  CFG_TEST_RE  = /\A#\[\s*cfg\s*\(\s*test\s*\)\s*\]\z/
  PATH_ATTR_RE = /\A#\[\s*path\s*=\s*"([^"]+)"\s*\]\z/

  def self.parse(source : String) : Imports
    imports = Imports.new
    Noir::TreeSitter.parse_rust(source) do |root|
      attrs = [] of String
      Noir::TreeSitter.each_named_child(root) do |item|
        type = Noir::TreeSitter.node_type(item)
        if type == "attribute_item"
          attrs << Noir::TreeSitter.node_text(item, source).gsub(/\s+/, " ")
          next
        end
        next if type == "line_comment" || type == "block_comment"
        item_attrs = attrs
        attrs = [] of String
        next if item_attrs.any?(&.matches?(CFG_TEST_RE))
        case type
        when "use_declaration"
          arg = Noir::TreeSitter.field(item, "argument") || next
          pub = Noir::TreeSitter.node_text(item, source).starts_with?("pub")
          collect(arg, "", pub, source, imports, 0)
        when "function_item"
          if name = Noir::TreeSitter.field(item, "name")
            imports.fns[Noir::TreeSitter.node_text(name, source).lchop("r#")] ||= Noir::TreeSitter.node_start_row(name) + 1
          end
        when "mod_item"
          name = Noir::TreeSitter.field(item, "name") || next
          mod_name = Noir::TreeSitter.node_text(name, source)
          imports.mods << mod_name
          item_attrs.each do |attr|
            if m = attr.match(PATH_ATTR_RE)
              imports.mod_paths[mod_name] = m[1]
            end
          end
        end
      end
    end
    imports
  end

  private def self.collect(node : LibTreeSitter::TSNode, prefix : String, pub : Bool,
                           source : String, imports : Imports, depth : Int32)
    return if depth > 16
    case Noir::TreeSitter.node_type(node)
    when "use_as_clause"
      path = Noir::TreeSitter.field(node, "path") || return
      alias_node = Noir::TreeSitter.field(node, "alias") || return
      local = Noir::TreeSitter.node_text(alias_node, source)
      add(imports, local, self_path(join(prefix, Noir::TreeSitter.node_text(path, source))), pub) unless local == "_"
    when "scoped_use_list"
      inner = Noir::TreeSitter.field(node, "path").try { |p| join(prefix, Noir::TreeSitter.node_text(p, source)) } || prefix
      list = Noir::TreeSitter.field(node, "list") || return
      collect(list, inner, pub, source, imports, depth + 1)
    when "use_list"
      Noir::TreeSitter.each_named_child(node) { |child| collect(child, prefix, pub, source, imports, depth + 1) }
    when "use_wildcard"
      path = join(prefix, Noir::TreeSitter.node_text(node, source).rchop("*").rchop("::"))
      imports.globs << path
      imports.pub_globs << path if pub
    when "identifier", "scoped_identifier", "self", "crate", "super"
      full = self_path(join(prefix, Noir::TreeSitter.node_text(node, source)))
      add(imports, full.split("::").last, full, pub)
    end
  end

  # `a::b::self` (from `use a::b::{self}`) names `a::b`.
  private def self.self_path(path : String) : String
    path.ends_with?("::self") ? path.rchop("::self") : path
  end

  private def self.add(imports : Imports, local : String, full : String, pub : Bool)
    local = local.lchop("r#")
    return if imports.ambiguous.includes?(local)
    if (existing = imports.names[local]?) && existing != full
      imports.names.delete(local)
      imports.pub_names.delete(local)
      imports.ambiguous << local
      return
    end
    imports.names[local] = full
    imports.pub_names << local if pub
  end

  private def self.join(prefix : String, path : String) : String
    path = path.gsub(/\s+/, "").lchop("::")
    return path if prefix.empty?
    return prefix if path.empty?
    "#{prefix}::#{path}"
  end
end
