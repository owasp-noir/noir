require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

# Pool reuse is the optimisation that makes monorepo scans avoid
# re-paying `ts_parser_new` + `ts_parser_set_language` per file. The
# specs lock the contract: after a `parse` call returns, a parser sits
# idle in the language bucket; the next call pops it instead of
# allocating a fresh one.
describe "Noir::TreeSitter parser pool" do
  it "keeps an idle parser in the pool after a parse call returns" do
    # The pool is module-level state and other specs in the same
    # run may have warmed it (e.g., any spec that exercises a
    # Python miniparser). When the pool already has a parser, the
    # `parse` call below pops it on checkout and pushes it back on
    # checkin, leaving the size unchanged — so the meaningful
    # contract is "at least one idle parser exists after parse
    # returns", not strictly `before + 1`.
    language = LibTreeSitter.tree_sitter_python
    Noir::TreeSitter.parse_python("x = 1") { |_| }
    Noir::TreeSitter.parser_pool_size(language).should be >= 1
  end

  it "reuses the pooled parser on the next parse call" do
    language = LibTreeSitter.tree_sitter_go
    # Prime the pool.
    Noir::TreeSitter.parse_go("package main") { |_| }
    primed = Noir::TreeSitter.parser_pool_size(language)
    primed.should be >= 1

    # Reusing the parser must not grow the pool.
    Noir::TreeSitter.parse_go("package main") { |_| }
    Noir::TreeSitter.parser_pool_size(language).should eq(primed)
  end

  it "produces equivalent parse results across pooled invocations" do
    source = "fn handler() {}"

    first_types = [] of String
    second_types = [] of String

    collect = ->(into : Array(String), root : LibTreeSitter::TSNode) do
      walk = uninitialized Proc(LibTreeSitter::TSNode, Nil)
      walk = ->(n : LibTreeSitter::TSNode) do
        into << Noir::TreeSitter.node_type(n)
        Noir::TreeSitter.each_named_child(n) { |c| walk.call(c) }
      end
      walk.call(root)
    end

    Noir::TreeSitter.parse_rust(source) { |root| collect.call(first_types, root) }
    Noir::TreeSitter.parse_rust(source) { |root| collect.call(second_types, root) }

    second_types.should eq(first_types)
    second_types.should contain("function_item")
  end

  it "isolates parsers per language" do
    py_before = Noir::TreeSitter.parser_pool_size(LibTreeSitter.tree_sitter_python)
    Noir::TreeSitter.parse_java("class A {}") { |_| }
    Noir::TreeSitter.parser_pool_size(LibTreeSitter.tree_sitter_python).should eq(py_before)
    Noir::TreeSitter.parser_pool_size(LibTreeSitter.tree_sitter_java).should be >= 1
  end
end
