require "../../func_spec.cr"

expected_endpoints = [
  # Basic controller endpoints
  Endpoint.new("/users", "GET", [] of Param),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # Query parameters
  Endpoint.new("/users/search", "GET", [
    Param.new("name", "", "query"),
    Param.new("email", "", "query"),
  ]),
  # Header parameters
  Endpoint.new("/protected", "GET", [
    Param.new("authorization", "", "header"),
  ]),
  # `@Controller()` (empty) — method path used as-is.
  Endpoint.new("/health", "GET", [] of Param),
  # `@Controller({ path: 'tasks', version: '1' })` (object).
  Endpoint.new("/tasks", "GET", [] of Param),
  Endpoint.new("/tasks", "POST", [
    Param.new("body", "", "body"),
  ]),
  # Multi-line `@Controller({ path: 'webhooks', ... })`.
  Endpoint.new("/webhooks/:provider", "POST", [
    Param.new("provider", "", "path"),
    Param.new("body", "", "body"),
  ]),
]

FunctionalTester.new("fixtures/typescript/nestjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
