require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "form"),
    Param.new("X-Token", "", "header"),
    Param.new("authorization", "", "header"),
    Param.new("session", "", "cookie"),
    Param.new("id", "", "json"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/items", "GET", [
    Param.new("id", "", "query"),
    Param.new("X-Auth", "", "header"),
    Param.new("x-auth", "", "header"),
  ]),
  Endpoint.new("/api/items", "DELETE", [
    Param.new("id", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/ruby/webrick/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
