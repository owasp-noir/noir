require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("limit", "", "query"),
    Param.new("cursor", "", "query"),
    Param.new("X-Auth", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # Huma v2 sugar helpers (path is the 2nd argument).
  Endpoint.new("/health", "GET", [
    Param.new("verbose", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/go/huma/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
