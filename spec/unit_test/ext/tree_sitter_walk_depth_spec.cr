require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

# `each_named_child` is the descent step practically every AST walker in
# the tree recurses through, so it is where the recursion bound lives.
# Without it a source file with thousands of nested syntactic constructs
# — `((((...))))`, a generated builder chain, machine-emitted code —
# recursed until the fiber stack ran out. A stack overflow is a hard
# abort: it takes down the whole scan, and none of the `rescue`s in
# `parallel_analyze` or `scan_files` can catch it.
describe "Noir::TreeSitter.each_named_child depth bound" do
  it "stops descending past MAX_AST_DEPTH" do
    nest = Noir::TreeSitter::MAX_AST_DEPTH + 500
    source = "x = #{"(" * nest}1#{")" * nest}\n"

    deepest = 0
    visit = uninitialized Proc(LibTreeSitter::TSNode, Int32, Nil)
    visit = ->(node : LibTreeSitter::TSNode, depth : Int32) do
      deepest = depth if depth > deepest
      Noir::TreeSitter.each_named_child(node) { |child| visit.call(child, depth + 1) }
    end

    Noir::TreeSitter.parse_python(source) { |root| visit.call(root, 0) }

    deepest.should be <= Noir::TreeSitter::MAX_AST_DEPTH
  end

  it "leaves the counter at rest after a walk completes" do
    source = "x = ((((1))))\n"
    Noir::TreeSitter.parse_python(source) do |root|
      Noir::TreeSitter.each_named_child(root) { |child| child }
    end

    Noir::TreeSitter.walk_depth.should eq(0)
  end

  it "restores the counter when a walker raises mid-descent" do
    source = "x = ((((1))))\n"

    expect_raises(Exception, "boom") do
      Noir::TreeSitter.parse_python(source) do |root|
        Noir::TreeSitter.each_named_child(root) do |child|
          Noir::TreeSitter.each_named_child(child) { raise "boom" }
        end
      end
    end

    Noir::TreeSitter.walk_depth.should eq(0)
  end

  it "still yields every named child of a shallow node" do
    source = "def f(a, b, c):\n    pass\n"

    top_level = [] of String
    Noir::TreeSitter.parse_python(source) do |root|
      Noir::TreeSitter.each_named_child(root) { |c| top_level << Noir::TreeSitter.node_type(c) }
    end

    top_level.should eq(["function_definition"])
  end
end
