require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

# Covers the `Noir::TreeSitter::Query` facade — compile a query once,
# run it against a parse tree, iterate the captures. These specs double
# as the documented authoring story for #1286: the query strings here
# are what a future detector would ship.
describe Noir::TreeSitter::Query do
  it "captures `@router` and `@path` for Flask-style decorators" do
    source = <<-PY
      from flask import Flask
      app = Flask(__name__)

      @app.route("/hello")
      def hello():
          return "world"

      @app.route("/items/<int:id>", methods=["GET", "POST"])
      def item(id):
          return str(id)
      PY

    query = Noir::TreeSitter::Query.new(
      LibTreeSitter.tree_sitter_python,
      <<-SCM
        (decorator
          (call
            function: (attribute
              object: (identifier) @router
              attribute: (identifier) @attr)
            arguments: (argument_list
              (string (string_content) @path))))
        SCM
    )
    begin
      hits = [] of Tuple(String, String, String)
      Noir::TreeSitter.parse_python(source) do |root|
        query.each_match_raw(root, source) do |_, caps|
          capture = caps.to_h
          hits << {
            Noir::TreeSitter.node_text(capture["router"], source),
            Noir::TreeSitter.node_text(capture["attr"], source),
            Noir::TreeSitter.node_text(capture["path"], source),
          }
        end
      end
      hits.should eq([
        {"app", "route", "/hello"},
        {"app", "route", "/items/<int:id>"},
      ])
    ensure
      query.close
    end
  end

  it "uses `#eq?` predicates to narrow matches to a specific attribute" do
    source = <<-PY
      app.route("/a")
      app.get("/b")
      app.post("/c")
      other.route("/d")
      PY

    # Filter to `.route` calls on a receiver named `app` only.
    query = Noir::TreeSitter::Query.new(
      LibTreeSitter.tree_sitter_python,
      <<-SCM
        (call
          function: (attribute
            object: (identifier) @router
            attribute: (identifier) @attr)
          arguments: (argument_list
            (string (string_content) @path))
          (#eq? @router "app")
          (#eq? @attr "route"))
        SCM
    )
    begin
      paths = [] of String
      Noir::TreeSitter.parse_python(source) do |root|
        query.each_match_raw(root, source) do |_, caps|
          paths << Noir::TreeSitter.node_text(caps.to_h["path"], source)
        end
      end
      paths.should eq(["/a"])
    ensure
      query.close
    end
  end

  it "raises CompileError when the query source is syntactically invalid" do
    expect_raises(Noir::TreeSitter::Query::CompileError, /failed to compile/) do
      Noir::TreeSitter::Query.new(
        LibTreeSitter.tree_sitter_python,
        "(this_is_not_a_valid_query",
      )
    end
  end

  it "raises CompileError on a predicate other than `#eq?`" do
    expect_raises(Noir::TreeSitter::Query::CompileError, /unsupported .*#match\?/) do
      Noir::TreeSitter::Query.new(
        LibTreeSitter.tree_sitter_python,
        %((identifier) @id (#match? @id "^a")),
      )
    end
  end
end
