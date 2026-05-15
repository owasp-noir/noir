require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

describe "Noir::TreeSitter.parse_rust" do
  it "parses an axum-style route registration into the expected node shape" do
    source = <<-RS
      use axum::{Router, routing::get};

      async fn hello() -> &'static str { "hi" }

      #[tokio::main]
      async fn main() {
          let app = Router::new().route("/hello", get(hello));
      }
      RS

    types = [] of String
    visit = uninitialized Proc(LibTreeSitter::TSNode, Nil)
    visit = ->(n : LibTreeSitter::TSNode) do
      ty = Noir::TreeSitter.node_type(n)
      types << ty unless ty.empty?
      Noir::TreeSitter.each_named_child(n) { |c| visit.call(c) }
    end
    Noir::TreeSitter.parse_rust(source) { |root| visit.call(root) }

    # tree-sitter-rust models receiver.method(args) as a `call_expression`
    # whose function is a `field_expression`; there is no dedicated
    # `method_call_expression` node type.
    types.should contain("function_item")
    types.should contain("call_expression")
    types.should contain("field_expression")
    types.should contain("scoped_identifier")
    types.should contain("string_literal")
  end

  it "extracts the path string from .route(\"/users\", ...)" do
    source = %(let app = Router::new().route("/users", get(list_users));)

    extracted = [] of String
    visit = uninitialized Proc(LibTreeSitter::TSNode, Nil)
    visit = ->(n : LibTreeSitter::TSNode) do
      if Noir::TreeSitter.node_type(n) == "string_content"
        extracted << Noir::TreeSitter.node_text(n, source)
      end
      Noir::TreeSitter.each_named_child(n) { |c| visit.call(c) }
    end
    Noir::TreeSitter.parse_rust(source) { |root| visit.call(root) }

    extracted.should contain("/users")
  end

  it "exposes macro_invocation for rocket-style #[get(...)] attributes" do
    source = <<-RS
      #[get("/api/v1/health")]
      fn health() -> &'static str { "ok" }
      RS

    found_attribute = false
    visit = uninitialized Proc(LibTreeSitter::TSNode, Nil)
    visit = ->(n : LibTreeSitter::TSNode) do
      found_attribute = true if Noir::TreeSitter.node_type(n) == "attribute_item"
      Noir::TreeSitter.each_named_child(n) { |c| visit.call(c) }
    end
    Noir::TreeSitter.parse_rust(source) { |root| visit.call(root) }

    found_attribute.should be_true
  end
end
