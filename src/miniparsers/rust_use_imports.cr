require "../ext/tree_sitter/tree_sitter"

# What a Rust file's top-level `use` declarations bring into scope, and
# which of its own items it defines, read from the tree:
#
#   use lemmy_api::{post::{create::create_post, save::save_post as save}};
#   pub use self::handlers::*;
#
# gives `create_post => lemmy_api::post::create::create_post`,
# `save => lemmy_api::post::save::save_post` and the glob
# `self::handlers` (public). Only the file's top level is read: a `use`
# inside a fn or an inline `mod` is scoped to that block.
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
  end

  def self.parse(source : String) : Imports
    imports = Imports.new
    Noir::TreeSitter.parse_rust(source) do |root|
      Noir::TreeSitter.each_named_child(root) do |item|
        case Noir::TreeSitter.node_type(item)
        when "use_declaration"
          arg = Noir::TreeSitter.field(item, "argument") || next
          pub = Noir::TreeSitter.node_text(item, source).starts_with?("pub")
          collect(arg, "", pub, source, imports, 0)
        when "function_item"
          if name = Noir::TreeSitter.field(item, "name")
            imports.fns[Noir::TreeSitter.node_text(name, source)] ||= Noir::TreeSitter.node_start_row(name) + 1
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
      add(imports, local, join(prefix, Noir::TreeSitter.node_text(path, source)), pub) unless local == "_"
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
      full = join(prefix, Noir::TreeSitter.node_text(node, source))
      parts = full.split("::")
      parts.pop if parts.last == "self" && parts.size > 1
      add(imports, parts.last, parts.join("::"), pub)
    end
  end

  private def self.add(imports : Imports, local : String, full : String, pub : Bool)
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
