require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

# `each_named_child` is the descent step practically every AST walker in
# the tree recurses through, so it is where the recursion bound lives.
# Without it a source file with thousands of nested syntactic constructs
# — `((((...))))`, a generated builder chain, machine-emitted code —
# recursed until the fiber stack ran out. A stack overflow is a hard
# abort: it takes down the whole scan, and none of the `rescue`s in
# `parallel_analyze` or `scan_files` can catch it.
# Deepest level a walk over a file nested well past MAX_AST_DEPTH reaches.
# A depth counter left standing by an earlier walk would cut this one short.
private def deepest_reach : Int32
  nest = Noir::TreeSitter::MAX_AST_DEPTH + 500
  source = "x = #{"(" * nest}1#{")" * nest}\n"

  deepest = 0
  visit = uninitialized Proc(LibTreeSitter::TSNode, Int32, Nil)
  visit = ->(node : LibTreeSitter::TSNode, depth : Int32) do
    deepest = depth if depth > deepest
    Noir::TreeSitter.each_named_child(node) { |child| visit.call(child, depth + 1) }
  end

  Noir::TreeSitter.parse_python(source) { |root| visit.call(root, 0) }
  deepest
end

describe "Noir::TreeSitter.each_named_child depth bound" do
  # Every assertion below runs on the spec's own fiber, and the counter is
  # per fiber, so walks in other specs (or other fibers) cannot skew it.
  it "starts the spec at rest" do
    Fiber.current.noir_ts_walk_depth.should eq(0)
  end

  it "stops descending at MAX_AST_DEPTH" do
    deepest_reach.should eq(Noir::TreeSitter::MAX_AST_DEPTH)
  end

  it "leaves the counter at rest after a walk completes" do
    source = "x = ((((1))))\n"
    Noir::TreeSitter.parse_python(source) do |root|
      Noir::TreeSitter.each_named_child(root) { |child| child }
    end

    deepest_reach.should eq(Noir::TreeSitter::MAX_AST_DEPTH)
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

    deepest_reach.should eq(Noir::TreeSitter::MAX_AST_DEPTH)
  end

  # Two fibers on one thread, each suspended inside a walk, unwind out of
  # order. A thread-wide counter came back at 1 here and cut every later
  # walk on the thread one level short (#3115).
  it "keeps the counter per fiber when walks interleave" do
    inside = [] of Int32
    after = [] of Int32
    done = Channel(Nil).new

    2.times do
      spawn do
        Noir::TreeSitter.parse_python("x = ((1))\n") do |root|
          Noir::TreeSitter.each_named_child(root) do
            inside << Fiber.current.noir_ts_walk_depth
            Fiber.yield
          end
        end
        after << Fiber.current.noir_ts_walk_depth
        done.send(nil)
      end
    end
    2.times { done.receive }

    inside.should eq([1, 1])
    after.should eq([0, 0])
    Fiber.current.noir_ts_walk_depth.should eq(0)
    deepest_reach.should eq(Noir::TreeSitter::MAX_AST_DEPTH)
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
