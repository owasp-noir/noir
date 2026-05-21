require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [Param.new("body", "User", "json")]),
  Endpoint.new("/api/v1/items/{itemId}", "PUT", [
    Param.new("itemId", "", "path"),
    Param.new("Authorization", "", "header"),
    Param.new("body", "Item", "json"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "DELETE", [
    Param.new("itemId", "", "path"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/api/v1/items", "GET", [
    Param.new("category", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/session", "GET", [Param.new("sessionId", "", "cookie")]),
  Endpoint.new("/ping", "GET"),
]

FunctionalTester.new("fixtures/scala/tapir/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
