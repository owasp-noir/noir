require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("Authorization", "Bearer token123", "header"),
    Param.new("Accept", "application/json", "header"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/api/users/123", "PUT", [
    Param.new("name", "", "form"),
    Param.new("email", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/caido/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
