require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "User", "json"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "User", "json"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [
    Param.new("body", "Submission", "json"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/sessions/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/profile", "PATCH", [
    Param.new("email", "", "form"),
    Param.new("phone", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/java/javalin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
