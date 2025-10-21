require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("Authorization", "Bearer token123", "header"),
    Param.new("page", "1", "query"),
    Param.new("limit", "10", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "John Doe", "json"),
    Param.new("email", "john@example.com", "json"),
  ]),
  Endpoint.new("/users/:userId", "PUT", [
    Param.new("userId", "123", "path"),
    Param.new("name", "Jane Doe", "form"),
    Param.new("email", "jane@example.com", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/postman/common/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
