require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/:id", "GET", [
    Param.new("x-trace", "", "header"),
  ]),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/api/v1/submit", "POST", [
    Param.new("body", "", "json"),
    Param.new("x-token", "", "header"),
  ]),
  Endpoint.new("/api/v1/items/:itemId", "GET", [
    Param.new("category", "", "query"),
  ]),
  Endpoint.new("/sessions/:id", "DELETE", [
    Param.new("session", "", "cookie"),
  ]),
  # `.all('/health', ...)` fans out to GET / POST / PUT / DELETE / PATCH.
  Endpoint.new("/health", "GET"),
  Endpoint.new("/health", "POST"),
  Endpoint.new("/health", "PUT"),
  Endpoint.new("/health", "DELETE"),
  Endpoint.new("/health", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/elysia/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
