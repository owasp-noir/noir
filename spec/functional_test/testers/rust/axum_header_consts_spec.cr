require "../../func_spec.cr"

# `headers.get(AUTHORIZATION)` / `header::USER_AGENT` read the header the
# `http::header` constant names. A crate-local const is not guessed at.
expected_endpoints = [
  Endpoint.new("/literal", "GET", [Param.new("x-api-key", "", "header")]),
  Endpoint.new("/consts", "GET", [
    Param.new("authorization", "", "header"),
    Param.new("user-agent", "", "header"),
    Param.new("if-none-match", "", "header"),
  ]),
]

tester = FunctionalTester.new("fixtures/rust/axum_header_consts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
})
tester.perform_tests

it "reads no header from a crate-local const", tags: "functional" do
  consts = tester.app.endpoints.find! { |ep| ep.url == "/consts" }
  consts.params.map(&.name).sort!.should eq(["authorization", "if-none-match", "user-agent"])
end
