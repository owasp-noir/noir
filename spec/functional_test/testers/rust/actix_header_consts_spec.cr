require "../../func_spec.cr"

# `req.headers().get(header::AUTHORIZATION)`: an `http::header` constant
# names the standard header it stands for.
expected_endpoints = [
  Endpoint.new("/literal", "GET", [Param.new("x-api-key", "", "header")]),
  Endpoint.new("/consts", "GET", [
    Param.new("authorization", "", "header"),
    Param.new("user-agent", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/rust/actix_header_consts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
