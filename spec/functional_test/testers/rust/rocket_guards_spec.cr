require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/me", "GET"),
  Endpoint.new("/api/org/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/client", "GET"),
  Endpoint.new("/api/maybe", "GET"),
  Endpoint.new("/api/hint", "GET"),
  # `Json<LoginData>`: serde's rename_all / rename / skip and `r#` decide
  # the wire names, not the `data` binding.
  Endpoint.new("/api/login", "POST", [
    Param.new("userName", "", "json"),
    Param.new("pw", "", "json"),
    Param.new("type", "", "json"),
  ]),
  # Rocket `#[field(name = "...")]` renames a `FromForm` field.
  Endpoint.new("/api/login-form", "POST", [
    Param.new("start", "", "form"),
    Param.new("continuationToken", "", "form"),
  ]),
  # `?<range..>` spreads the query over `Range`'s fields.
  Endpoint.new("/api/events", "GET", [
    Param.new("start", "", "query"),
    Param.new("continuationToken", "", "query"),
  ]),
  # `Value` is no struct of the crate: keep the binding.
  Endpoint.new("/api/raw", "POST", [Param.new("raw", "", "body")]),
]

tester = FunctionalTester.new("fixtures/rust/rocket_guards/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the fn under a route attribute as its handler, past doc comments and attributes", tags: "functional" do
  main_rs = "./spec/functional_test/fixtures/rust/rocket_guards/src/main.rs"
  me = tester.app.endpoints.find! { |ep| ep.url == "/api/me" }
  me.handler.should eq(Handler.new("me", main_rs, 30))
  org = tester.app.endpoints.find! { |ep| ep.url == "/api/org/{id}" }
  org.handler.should eq(Handler.new("delete_org", main_rs, 37))
end
