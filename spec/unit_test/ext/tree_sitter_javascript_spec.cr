require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

describe "Noir::TreeSitter.parse_javascript" do
  it "parses a simple Express-style call into the expected node shape" do
    source = <<-JS
      const app = express();
      app.get('/users/:id', (req, res) => res.send('ok'));
      JS

    types = [] of String
    visit = uninitialized Proc(LibTreeSitter::TSNode, Nil)
    visit = ->(n : LibTreeSitter::TSNode) do
      ty = Noir::TreeSitter.node_type(n)
      types << ty unless ty.empty?
      Noir::TreeSitter.each_named_child(n) { |c| visit.call(c) }
    end
    Noir::TreeSitter.parse_javascript(source) { |root| visit.call(root) }

    types.should contain("call_expression")
    types.should contain("member_expression")
    types.should contain("arrow_function")
    types.should contain("string")
  end

  it "extracts the path argument from app.get('/x', handler)" do
    source = "app.get('/x', () => {});"

    extracted = ""
    visit = uninitialized Proc(LibTreeSitter::TSNode, Nil)
    visit = ->(n : LibTreeSitter::TSNode) do
      if Noir::TreeSitter.node_type(n) == "string_fragment"
        extracted = Noir::TreeSitter.node_text(n, source) if extracted.empty?
      end
      Noir::TreeSitter.each_named_child(n) { |c| visit.call(c) }
    end
    Noir::TreeSitter.parse_javascript(source) { |root| visit.call(root) }

    extracted.should eq("/x")
  end

  it "handles arrow-function bodies with statement blocks" do
    source = <<-JS
      app.post('/users', (req, res) => {
          const name = req.body.name;
          res.send(name);
      });
      JS

    found_block = false
    visit = uninitialized Proc(LibTreeSitter::TSNode, Nil)
    visit = ->(n : LibTreeSitter::TSNode) do
      found_block = true if Noir::TreeSitter.node_type(n) == "statement_block"
      Noir::TreeSitter.each_named_child(n) { |c| visit.call(c) }
    end
    Noir::TreeSitter.parse_javascript(source) { |root| visit.call(root) }

    found_block.should be_true
  end
end
