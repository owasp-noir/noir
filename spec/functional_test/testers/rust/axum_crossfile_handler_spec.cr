require "../../func_spec.cr"

# `get(capabilities_endpoint)` names a fn of a sibling workspace crate through
# an `as` alias; `Json<T>` / `Json<Vec<T>>` read `T`'s wire field names, `T`
# imported from that crate; `Query<T>` of a field-less struct reads nothing.
# A same-named impl method never stands in for the free fn `login`, a
# `#[serde(flatten)]` field contributes its type's fields (an unknown one
# adds the placeholder beside the known fields), a bare struct name means
# the top-level struct, not one of an inline `mod`, and a fn's own type
# parameter names no struct.
login_params = [
  Param.new("username", "", "json"),
  Param.new("password", "", "json"),
  Param.new("totp_code", "", "json"),
]
expected_endpoints = [
  Endpoint.new("/login", "POST", login_params),
  Endpoint.new("/signin", "POST", login_params),
  Endpoint.new("/records", "POST", [
    Param.new("id", "", "json"),
    Param.new("tag", "", "json"),
    Param.new("data", "", "json"),
  ]),
  Endpoint.new("/store", "DELETE"),
  Endpoint.new("/list", "GET", [
    Param.new("page", "", "query"),
    Param.new("per_page", "", "query"),
  ]),
  Endpoint.new("/search", "POST", [
    Param.new("q", "", "json"),
    Param.new("page", "", "json"),
    Param.new("per_page", "", "json"),
  ]),
  Endpoint.new("/loose", "POST", [Param.new("kind", "", "json"), Param.new("body", "", "json")]),
  Endpoint.new("/generic", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/capabilities", "GET"),
]

tester = FunctionalTester.new("fixtures/rust/axum_crossfile_handler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "resolves cross-crate handlers and reads extractor types by their definition", tags: "functional" do
  base = "./spec/functional_test/fixtures/rust/axum_crossfile_handler"
  by_key = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep} }
  by_key["GET /capabilities"].handler.should eq(Handler.new("get", "#{base}/domain/src/caps/axum.rs", 3))
  login = Handler.new("login", "#{base}/server/src/handlers.rs", 18)
  by_key["POST /login"].handler.should eq(login)
  by_key["POST /signin"].handler.should eq(login)
  by_key["DELETE /store"].params.should be_empty
  by_key.each_value do |ep|
    names = ep.params.map(&.name)
    names.should_not contain("wrong_field")
    names.should_not contain("old_name")
    names.should_not contain("unrelated")
  end
  by_key["POST /records"].params.map(&.name).should_not contain("body")
  by_key["POST /loose"].params.map(&.name).should eq(["kind", "body"])
end
