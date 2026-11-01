require "spec"
require "../../../src/ext/tree_sitter/tree_sitter"

describe "Noir::TreeSitter.parse_typescript" do
  it "parses a TypeScript snippet with generics, type annotations, decorators, and as casts without errors" do
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

    Noir::TreeSitter.parse_typescript(source) do |root|
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
end

describe "Noir::TreeSitter.parse_tsx" do
  it "parses a TSX snippet with JSX and TypeScript types without errors" do
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

    Noir::TreeSitter.parse_tsx(source) do |root|
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
end
