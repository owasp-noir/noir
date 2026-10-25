require "../../func_spec.cr"

# `get(capabilities_endpoint)` names a fn of a sibling workspace crate through
# an `as` alias; `Json<T>` / `Json<Vec<T>>` read `T`'s wire field names, `T`
# imported from that crate; `Query<T>` of a field-less struct reads nothing.
expected_endpoints = [
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
    Param.new("totp_code", "", "json"),
  ]),
  Endpoint.new("/records", "POST", [
    Param.new("id", "", "json"),
    Param.new("tag", "", "json"),
    Param.new("data", "", "json"),
  ]),
  Endpoint.new("/store", "DELETE"),
  Endpoint.new("/capabilities", "GET"),
]

tester = FunctionalTester.new("fixtures/rust/axum_crossfile_handler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "resolves cross-crate handlers and reads no placeholder for a field-less extractor", tags: "functional" do
  base = "./spec/functional_test/fixtures/rust/axum_crossfile_handler"
  by_key = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep} }
  by_key["GET /capabilities"].handler.should eq(Handler.new("get", "#{base}/domain/src/caps/axum.rs", 3))
  by_key["POST /login"].handler.should eq(Handler.new("login", "#{base}/server/src/handlers.rs", 6))
  by_key["DELETE /store"].params.should be_empty
  by_key["POST /records"].params.map(&.name).should_not contain("body")
end
