require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("body", "", "json"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/api/health", "GET", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("title", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/go/http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
