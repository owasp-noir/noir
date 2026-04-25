require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [
    Param.new("body", "", "json"),
    Param.new("X-Token", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/:itemId", "GET", [
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/sessions/:id", "DELETE", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/profile", "PUT", [
    Param.new("body", "", "json"),
    Param.new("X-Trace", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/java/spark/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
