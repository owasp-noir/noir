require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [Param.new("body", "User", "json")]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("id", "", "query"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [Param.new("body", "SubmitData", "json")]),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("itemId", "", "query"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/partial/{resourceId}", "PATCH", [
    Param.new("resourceId", "", "path"),
    Param.new("resourceId", "", "query"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/check/{id}", "HEAD", [
    Param.new("id", "", "path"),
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/settings", "OPTIONS"),
]

FunctionalTester.new("fixtures/kotlin/ktor/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
