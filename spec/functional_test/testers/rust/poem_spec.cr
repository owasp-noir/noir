require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Token", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("query", "", "query"),
  ]),
  Endpoint.new("/items/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("form", "", "form"),
  ]),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/rust/poem/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
