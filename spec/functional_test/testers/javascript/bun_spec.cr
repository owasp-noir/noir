require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/version", "GET"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/api/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/webhook", "POST", [
    Param.new("event", "", "form"),
  ]),
  # Typed arrow + `switch (req.method)` dispatch.
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/api/items", "DELETE"),
  # `req.method !== "POST"` guard; casted, optional-chained json body.
  Endpoint.new("/api/upload", "POST", [
    Param.new("title", "", "json"),
  ]),
  # Pre-1.2.3 `static` map, options passed as an identifier.
  Endpoint.new("/legacy", "GET"),
]

FunctionalTester.new("fixtures/javascript/bun/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
