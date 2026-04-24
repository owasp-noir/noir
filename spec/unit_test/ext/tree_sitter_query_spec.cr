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
        query.each_match(root, source) do |capture|
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
        query.each_match(root, source) do |capture|
          paths << Noir::TreeSitter.node_text(capture["path"], source)
        end
      end
      paths.should eq(["/a"])
    ensure
      query.close
    end
  end

  it "supports alternation in the pattern to cover multiple verbs at once" do
    source = <<-GO
      package main
      func main() {
          r := gin.Default()
          r.GET("/x", h)
          r.POST("/y", h)
          r.Something("/z", h)
      }
      GO

    # Gin/Echo-style verb calls with the verb name as an identifier.
    # We constrain the `@verb` field to a fixed set via `#match?`.
    query = Noir::TreeSitter::Query.new(
      LibTreeSitter.tree_sitter_go,
      <<-SCM
        (call_expression
          function: (selector_expression
            operand: (identifier) @router
            field: (field_identifier) @verb)
          arguments: (argument_list
            (interpreted_string_literal
              (interpreted_string_literal_content) @path))
          (#match? @verb "^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)$"))
        SCM
    )
    begin
      hits = [] of Tuple(String, String)
      Noir::TreeSitter.parse_go(source) do |root|
        query.each_match(root, source) do |capture|
          hits << {
            Noir::TreeSitter.node_text(capture["verb"], source),
            Noir::TreeSitter.node_text(capture["path"], source),
          }
        end
      end
      hits.sort.should eq([{"GET", "/x"}, {"POST", "/y"}].sort)
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
end
