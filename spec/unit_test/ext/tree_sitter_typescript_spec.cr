require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

describe "Noir::TreeSitter.parse_js_family" do
  it "parses a .ts snippet with generics, type annotations, decorators, and as casts without errors" do
    source = <<-TS
      class Controller<T> {
        @Get(':id')
        find(@Param('id') id: string): Promise<Foo> {
          const result = raw as Foo;
          return Promise.resolve(result);
        }
      }
      TS

    types = [] of String
    has_error_node = false

    Noir::TreeSitter.parse_js_family(source, "users.controller.ts") do |root|
      LibTreeSitter.ts_node_has_error(root).should be_false
      Noir::TreeSitter.node_has_error?(root).should be_false

      Noir::TreeSitter.walk(root) do |n|
        ty = Noir::TreeSitter.node_type(n)
        has_error_node = true if ty == "ERROR"
        types << ty unless ty.empty?
      end
    end

    has_error_node.should be_false
    types.should contain("decorator")
    types.should contain("call_expression")
    types.should contain("type_annotation")
    types.should contain("type_arguments")
    types.should contain("as_expression")
  end

  it "parses a .tsx snippet with JSX and TypeScript types without errors" do
    source = <<-TSX
      interface Props<T> {
        item: T;
      }

      export const ItemView = <T,>({ item }: Props<T>) => {
        const label = item as string;
        return (
          <div className="item">
            <span>{label}</span>
          </div>
        );
      };
      TSX

    types = [] of String
    has_error_node = false

    Noir::TreeSitter.parse_js_family(source, "item_view.tsx") do |root|
      LibTreeSitter.ts_node_has_error(root).should be_false
      Noir::TreeSitter.node_has_error?(root).should be_false

      Noir::TreeSitter.walk(root) do |n|
        ty = Noir::TreeSitter.node_type(n)
        has_error_node = true if ty == "ERROR"
        types << ty unless ty.empty?
      end
    end

    has_error_node.should be_false
    types.should contain("jsx_element")
    types.should contain("interface_declaration")
    types.should contain("as_expression")
  end
  it "picks the grammar by extension" do
    Noir::TreeSitter.js_family_language("a.ts").should eq(LibTreeSitter.tree_sitter_typescript)
    Noir::TreeSitter.js_family_language("a.d.ts").should eq(LibTreeSitter.tree_sitter_typescript)
    Noir::TreeSitter.js_family_language("a.MTS").should eq(LibTreeSitter.tree_sitter_typescript)
    Noir::TreeSitter.js_family_language("a.cts").should eq(LibTreeSitter.tree_sitter_typescript)
    Noir::TreeSitter.js_family_language("a.tsx").should eq(LibTreeSitter.tree_sitter_tsx)
    Noir::TreeSitter.js_family_language("a.jsx").should eq(LibTreeSitter.tree_sitter_javascript)
    Noir::TreeSitter.js_family_language("a.mjs").should eq(LibTreeSitter.tree_sitter_javascript)
    Noir::TreeSitter.js_family_language("").should eq(LibTreeSitter.tree_sitter_javascript)
  end

  # `<T>x` is a type assertion in .ts and a JSX element in .tsx; the
  # wrong grammar for either turns the file into ERROR nodes.
  it "keeps .ts type assertions and .tsx JSX apart" do
    Noir::TreeSitter.parse_js_family("const a = <any>b;", "a.ts") do |root|
      Noir::TreeSitter.node_has_error?(root).should be_false
    end
    Noir::TreeSitter.parse_js_family("const a = <b>x</b>;", "a.tsx") do |root|
      Noir::TreeSitter.node_has_error?(root).should be_false
    end
  end
end

describe "Noir::TreeSitter.unwrap_expression" do
  it "peels parens, as / satisfies / non-null and <T> assertions" do
    source = "x = (y as any)! satisfies T as const;"
    Noir::TreeSitter.parse_js_family(source, "a.ts") do |root|
      assignment = Noir::TreeSitter.first_named_child(Noir::TreeSitter.first_named_child(root).not_nil!).not_nil!
      right = Noir::TreeSitter.field(assignment, "right").not_nil!
      inner = Noir::TreeSitter.unwrap_expression(right)
      Noir::TreeSitter.node_type(inner).should eq("identifier")
      Noir::TreeSitter.node_text(inner, source).should eq("y")
    end
    Noir::TreeSitter.parse_js_family("x = <T>(/* c */ y);", "a.ts") do |root|
      assignment = Noir::TreeSitter.first_named_child(Noir::TreeSitter.first_named_child(root).not_nil!).not_nil!
      inner = Noir::TreeSitter.unwrap_expression(Noir::TreeSitter.field(assignment, "right").not_nil!)
      Noir::TreeSitter.node_text(inner, "x = <T>(/* c */ y);").should eq("y")
    end
  end
end
