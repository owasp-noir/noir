require "../../func_spec.cr"

expected_endpoints = [
  # Basic controller endpoints
  Endpoint.new("/users", "GET", [] of Param),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # Query parameters
  Endpoint.new("/users/search", "GET", [
    Param.new("name", "", "query"),
    Param.new("email", "", "query"),
  ]),
  # Header parameters
  Endpoint.new("/protected", "GET", [
    Param.new("authorization", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nestjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
