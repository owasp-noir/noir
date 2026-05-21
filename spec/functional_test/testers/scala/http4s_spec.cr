require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users", "POST", [Param.new("body", "CreateUser", "json")]),
  Endpoint.new("/api/items/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "UpdateItem", "json"),
  ]),
  Endpoint.new("/api/search", "GET", [
    Param.new("name", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/v1/health", "GET"),
]

FunctionalTester.new("fixtures/scala/http4s/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
