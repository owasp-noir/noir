require "../../spec_helper"
require "../../../src/miniparsers/rust_routes_macro_extractor"

describe Noir::RustRoutesMacro do
  it "reads verbs, multi-verb lists and sub mounts, skipping comments and macro fragments" do
    source = <<-RUST
      #[routes::routes(
          routes(
              "" => [get(list), post(create)],
              // "/ghost" => get(ghost),
              "/{id}" => delete(remove),
              "/x" => sub(x::XApi),
              $( $route => get($attr::get) ),*
          ),
          tag = "T",
      )]
      pub struct ThingsApi;
      RUST
    tables = Noir::RustRoutesMacro.extract(source)
    tables.size.should eq 1
    tables[0].owner.should eq "ThingsApi"
    tables[0].entries.map { |e| {e.path, e.verb, e.handler, e.sub} }.should eq [
      {"", "GET", "list", nil},
      {"", "POST", "create", nil},
      {"/{id}", "DELETE", "remove", nil},
      {"/x", nil, nil, "x::XApi"},
    ]
    tables[0].entries[0].line.should eq 3
  end

  it "terminates on an unclosed attribute" do
    Noir::RustRoutesMacro.extract("#[routes::routes(routes(\"/a\" => get(a))\npub struct A;").should be_empty
  end

  it "ignores an attribute with no struct" do
    Noir::RustRoutesMacro.extract("#[derive(Debug)]\nstruct A;\n#[routes::routes(routes(\"/a\" => get(a)))]\nfn f() {}").should be_empty
  end
end
