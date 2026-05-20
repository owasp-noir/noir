require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "JSON", "body"),
  ]),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "body"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/users", "OPTIONS"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/search", "GET"),
]

FunctionalTester.new("fixtures/haskell/scotty/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
