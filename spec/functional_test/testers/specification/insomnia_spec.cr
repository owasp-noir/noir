require "../../func_spec.cr"

v4_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("page", "1", "query"),
    Param.new("limit", "10", "query"),
    Param.new("Authorization", "Bearer token123", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/users/:userId", "PUT", [
    Param.new("userId", "", "path"),
    Param.new("name", "Jane Doe", "form"),
    Param.new("email", "jane@example.com", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/insomnia/v4/", {
  :techs     => 1,
  :endpoints => v4_endpoints.size,
}, v4_endpoints).perform_tests

v5_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("page", "1", "query"),
    Param.new("limit", "10", "query"),
    Param.new("Authorization", "Bearer token123", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/insomnia/v5/", {
  :techs     => 1,
  :endpoints => v5_endpoints.size,
}, v5_endpoints).perform_tests

FunctionalTester.new("fixtures/specification/insomnia/folders/", {
  :techs     => 1,
  :endpoints => 2,
}, nil).perform_tests
