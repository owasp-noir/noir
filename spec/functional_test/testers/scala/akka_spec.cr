require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("body", "User", "json")]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/items", "GET", [
    Param.new("category", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/api/v1/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/items/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "Item", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/search", "POST", [Param.new("q", "", "query")]),
]

FunctionalTester.new("fixtures/scala/akka/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
