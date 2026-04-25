require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-trace", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "OPTIONS", [
    Param.new("id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/health", "POST"),
  Endpoint.new("/health", "PUT"),
  Endpoint.new("/health", "DELETE"),
  Endpoint.new("/health", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/hapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
