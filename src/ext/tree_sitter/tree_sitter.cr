# Crystal bindings for tree-sitter.
#
# Linked against the system-provided libtree-sitter runtime plus per-grammar
# object files that we vendor under `grammars/<lang>/`. Each grammar ships a
# large auto-generated `parser.c` and a small hand-written `scanner.c`.
#
# The ldflags backtick command auto-compiles each grammar when its source
# files are newer than the corresponding `.o`, mirroring the pattern used in
# sibling project `hwaro/src/ext/stb_bindings.cr`.
#
# Upstream versions currently vendored:
#   tree-sitter-python  v0.23.6

@[Link(ldflags: "`sh #{__DIR__}/build.sh`")]
lib LibTreeSitter
  # ----- Opaque types -----
  type TSParser = Void*
  type TSTree = Void*
  type TSLanguage = Void*
  type TSQuery = Void*
  type TSQueryCursor = Void*

  # ----- Structs exposed by api.h -----
  struct TSPoint
    row : LibC::UInt
    column : LibC::UInt
  end

  struct TSNode
    context : LibC::UInt[4]
    id : Void*
    tree : Void*
  end

  # ----- Parser lifecycle -----
  fun ts_parser_new : TSParser
  fun ts_parser_delete(parser : TSParser)
  fun ts_parser_set_language(parser : TSParser, language : TSLanguage) : Bool
  fun ts_parser_parse_string(parser : TSParser, old_tree : TSTree, string : LibC::Char*, length : LibC::UInt) : TSTree

  # ----- Tree / node -----
  fun ts_tree_delete(tree : TSTree)
  fun ts_tree_root_node(tree : TSTree) : TSNode
  fun ts_node_string(node : TSNode) : LibC::Char*
  fun ts_node_type(node : TSNode) : LibC::Char*
  fun ts_node_child_count(node : TSNode) : LibC::UInt
  fun ts_node_named_child_count(node : TSNode) : LibC::UInt
  fun ts_node_named_child(node : TSNode, index : LibC::UInt) : TSNode
  fun ts_node_child(node : TSNode, index : LibC::UInt) : TSNode
  fun ts_node_child_by_field_name(node : TSNode, name : LibC::Char*, name_length : LibC::UInt) : TSNode
  fun ts_node_start_byte(node : TSNode) : LibC::UInt
  fun ts_node_end_byte(node : TSNode) : LibC::UInt
  fun ts_node_start_point(node : TSNode) : TSPoint
  fun ts_node_end_point(node : TSNode) : TSPoint
  fun ts_node_is_null(node : TSNode) : Bool

  # ----- Grammars (linked from vendored parser.o) -----
  fun tree_sitter_python : TSLanguage
  fun tree_sitter_go : TSLanguage
end

# Thin high-level facade. Keeps tree lifetime tied to an object so callers
# don't have to think about `ts_tree_delete`.
module Noir::TreeSitter
  # Parses `source` with the given `language` and yields the root
  # `LibTreeSitter::TSNode`. The parser and tree are freed when the
  # block returns.
  def self.parse(source : String, language : LibTreeSitter::TSLanguage, &)
    parser = LibTreeSitter.ts_parser_new
    raise "ts_parser_new returned null" if parser.null?
    begin
      unless LibTreeSitter.ts_parser_set_language(parser, language)
        raise "ts_parser_set_language failed (ABI mismatch?)"
      end
      tree = LibTreeSitter.ts_parser_parse_string(parser, Pointer(Void).null.as(LibTreeSitter::TSTree), source.to_unsafe, source.bytesize.to_u32)
      raise "ts_parser_parse_string returned null" if tree.null?
      begin
        yield LibTreeSitter.ts_tree_root_node(tree)
      ensure
        LibTreeSitter.ts_tree_delete(tree)
      end
    ensure
      LibTreeSitter.ts_parser_delete(parser)
    end
  end

  # Parses `source` with the Python grammar and yields the root node.
  def self.parse_python(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_python) { |root| yield root }
  end

  # Parses `source` with the Go grammar and yields the root node.
  def self.parse_go(source : String, &)
    parse(source, LibTreeSitter.tree_sitter_go) { |root| yield root }
  end

  # Convenience: returns the root-node s-expression for `source`.
  def self.python_sexp(source : String) : String
    parse_python(source) do |root|
      ptr = LibTreeSitter.ts_node_string(root)
      begin
        String.new(ptr)
      ensure
        # ts_node_string allocates with malloc; free it.
        LibC.free(ptr.as(Void*))
      end
    end
  end

  # --- Small helpers used by extractors. Kept here so callers don't
  # have to touch LibTreeSitter directly. ---

  def self.node_type(node : LibTreeSitter::TSNode) : String
    String.new(LibTreeSitter.ts_node_type(node))
  end

  def self.node_text(node : LibTreeSitter::TSNode, source : String) : String
    sb = LibTreeSitter.ts_node_start_byte(node).to_i
    eb = LibTreeSitter.ts_node_end_byte(node).to_i
    source.byte_slice(sb, eb - sb)
  end

  def self.node_start_row(node : LibTreeSitter::TSNode) : Int32
    LibTreeSitter.ts_node_start_point(node).row.to_i
  end

  def self.field(node : LibTreeSitter::TSNode, name : String) : LibTreeSitter::TSNode?
    child = LibTreeSitter.ts_node_child_by_field_name(node, name.to_unsafe, name.bytesize.to_u32)
    LibTreeSitter.ts_node_is_null(child) ? nil : child
  end

  # Iterates named children without allocating an array.
  def self.each_named_child(node : LibTreeSitter::TSNode, &)
    count = LibTreeSitter.ts_node_named_child_count(node)
    count.times do |i|
      yield LibTreeSitter.ts_node_named_child(node, i.to_u32)
    end
  end
end

lib LibC
  fun free(ptr : Void*)
end
