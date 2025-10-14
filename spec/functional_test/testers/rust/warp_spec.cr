require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/:param", "GET", [
    Param.new("param", "", "path"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("SearchQuery", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("CreateUser", "", "json"),
  ]),
  Endpoint.new("/protected", "GET", [
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/session", "GET", [
    Param.new("session_id", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/rust/warp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
