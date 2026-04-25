require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("X-API-Key", "", "header"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [
    Param.new("body", "", "json"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/sessions/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/profile", "PATCH", [
    Param.new("email", "", "form"),
    Param.new("phone", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/kotlin/http4k/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
