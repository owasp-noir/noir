require "../../func_spec.cr"

# `.to(create_post)` names a fn imported from a sibling workspace crate
# (`my-api`, used as `my_api`) through a nested `use` tree and an `as`
# alias; `items::list` reaches its fn through a `pub use handlers::*`
# re-export. Extractor params are the decoded type's wire field names.
expected_endpoints = [
  Endpoint.new("/api/post", "POST", [
    Param.new("title", "", "json"),
    Param.new("communityId", "", "json"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/post", "GET", [
    Param.new("id", "", "query"),
    Param.new("comment_id", "", "query"),
  ]),
  Endpoint.new("/api/items", "GET"),
]

tester = FunctionalTester.new("fixtures/rust/actix_crossfile_handler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the fn a builder route resolves to across crates and re-exports", tags: "functional" do
  api = "./spec/functional_test/fixtures/rust/actix_crossfile_handler/api/src"
  handlers = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.handler} }
  handlers["POST /api/post"].should eq(Handler.new("create_post", "#{api}/posts/create.rs", 4))
  handlers["GET /api/post"].should eq(Handler.new("get_post", "#{api}/posts/read.rs", 4))
  handlers["GET /api/items"].should eq(Handler.new("list", "#{api}/items/handlers.rs", 4))
end
