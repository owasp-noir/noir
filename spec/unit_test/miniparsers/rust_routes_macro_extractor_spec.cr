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

  it "binds record keys through the matcher's metavariables, not by name" do
    source = <<-RUST
      macro_rules! mk {
          ($({route: $r:literal, update_verb: $uv:ident, attr: $a:ident},)*) => {
              pub mod $a {}
              #[routes::routes(routes(
                  $( $r => [get($a::get), $uv($a::update)] ),*
              ))]
              pub struct Api;
          };
      }
      mk!(
          {route: "/x", update_verb: put, attr: xx},
      );
      RUST
    entries = Noir::RustRoutesMacro.extract(source)[0].entries
    entries.map { |e| {e.path, e.verb, e.handler, e.generated} }.should eq [
      {"/x", "GET", "xx::get", true},
      {"/x", "PUT", "xx::update", true},
    ]
  end

  it "reads values with arrows, generics and comparisons, and keeps later records" do
    source = <<-RUST
      macro_rules! mk {
          ($({route: $r:literal, value_type: $t:ty, extra: $e:expr, attr: $a:ident},)*) => {
              #[routes::routes(routes(
                  $( $r => get($a::get) ),*
              ))]
              pub struct Api;
          };
      }
      mk!(
          {route: "/arrow", value_type: fn(u32) -> u32, extra: 1, attr: aa},
          {route: "/map", value_type: HashMap<String, u32>, extra: 1 < 2, attr: bb},
          {route: "/last", value_type: u8, extra: 3, attr: cc},
      );
      RUST
    Noir::RustRoutesMacro.extract(source)[0].entries.map(&.path).should eq ["/arrow", "/map", "/last"]
  end

  it "expands only invocations the table's own arm accepts" do
    source = <<-RUST
      macro_rules! mk {
          ({route: $r:literal, attr: $a:ident}) => {
              pub mod $a {}
          };
          ($({route: $r:literal, attr: $a:ident},)*) => {
              #[routes::routes(routes(
                  $( $r => get($a::get) ),*
              ))]
              pub struct Api;
          };
      }
      mk!({route: "/single", attr: one});
      mk!({route: "/b1", attr: b1}, {route: "/b2", attr: b2},);
      RUST
    Noir::RustRoutesMacro.extract(source)[0].entries.map(&.path).should eq ["/b1", "/b2"]
  end

  it "does not mark a handler of an unrelated module as macro-generated" do
    source = <<-RUST
      macro_rules! mk {
          ($({route: $r:literal, attr: $a:ident},)*) => {
              pub mod $a {}
              #[routes::routes(routes(
                  "/ext" => get(external_crate::get),
                  $( $r => get($a::get) ),*
              ))]
              pub struct Api;
          };
      }
      mk!({route: "/in", attr: inner},);
      RUST
    Noir::RustRoutesMacro.extract(source)[0].entries.map { |e| {e.path, e.generated} }.should eq [{"/ext", false}, {"/in", true}]
  end

  it "terminates on an unclosed attribute" do
    Noir::RustRoutesMacro.extract("#[routes::routes(routes(\"/a\" => get(a))\npub struct A;").should be_empty
  end

  it "ignores an attribute with no struct" do
    Noir::RustRoutesMacro.extract("#[derive(Debug)]\nstruct A;\n#[routes::routes(routes(\"/a\" => get(a)))]\nfn f() {}").should be_empty
  end
end
