require "../../func_spec.cr"

# Handler-name resolution edge cases (src/main.rs):
# - `#[cfg(test)] use crate::mock::list_items;` is not the production import;
# - `impl State { fn show_item }` does not shadow `use crate::handlers::show_item`;
# - `use api::v1::{self as v}` names the module `api::v1`;
# - `#[path = "other/real_impl.rs"] mod pathmod;` beats the decoy `src/pathmod.rs`;
# - `crate::Paging` in a module only `main.rs` declares is main.rs's struct;
# - `api::v1::missing` runs into a `pub use` cycle and names no handler.
expected_endpoints = [
  Endpoint.new("/items", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/item", "GET", [Param.new("cursor", "", "query")]),
  Endpoint.new("/alias", "GET"),
  Endpoint.new("/path", "GET"),
  Endpoint.new("/cyc", "GET"),
]

tester = FunctionalTester.new("fixtures/rust/actix_resolution_edges/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "resolves each builder handler to its real definition, or to none", tags: "functional" do
  src = "./spec/functional_test/fixtures/rust/actix_resolution_edges/src"
  handlers = tester.app.endpoints.to_h { |ep| {ep.url, ep.handler} }
  handlers["/items"].should eq(Handler.new("list_items", "#{src}/handlers/mod.rs", 4))
  handlers["/item"].should eq(Handler.new("show_item", "#{src}/handlers/mod.rs", 8))
  handlers["/alias"].should eq(Handler.new("show", "#{src}/api/v1.rs", 8))
  handlers["/path"].should eq(Handler.new("real", "#{src}/other/real_impl.rs", 3))
  handlers["/cyc"].should be_nil
  tester.app.endpoints.find!(&.url.==("/cyc")).params.should be_empty
end
