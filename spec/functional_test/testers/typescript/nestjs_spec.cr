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
  # `@Controller({ path: 'tasks', version: '1' })` — versioned
  # controllers route under `/v<version>` per Nest URI versioning.
  Endpoint.new("/v1/tasks", "GET", [] of Param),
  Endpoint.new("/v1/tasks", "POST", [
    Param.new("body", "", "body"),
  ]),
  # Multi-line `@Controller({ path: 'webhooks', version: '1' })`.
  Endpoint.new("/v1/webhooks/:provider", "POST", [
    Param.new("provider", "", "path"),
    Param.new("body", "", "body"),
  ]),
  # Constant / enum / object-member route names and pipe-bearing params.
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("includeInactive", "", "query"),
    Param.new("x-tenant-id", "", "header"),
  ]),
  # Method-level path arrays.
  Endpoint.new("/api/users/bulk", "POST", [
    Param.new("name", "", "body"),
  ]),
  Endpoint.new("/api/users/import", "POST", [
    Param.new("name", "", "body"),
  ]),
  # @Body(pipe) still marks the whole request body.
  Endpoint.new("/api/users/profile", "PATCH", [
    Param.new("body", "", "body"),
  ]),
  # Controller-level path arrays and non-exported controller classes.
  Endpoint.new("/public/health", "GET", [] of Param),
  Endpoint.new("/internal/health", "GET", [] of Param),
  # export default class plus @All expansion.
  Endpoint.new("/admin/status", "GET", [] of Param),
  Endpoint.new("/admin/status", "POST", [] of Param),
  Endpoint.new("/admin/status", "PUT", [] of Param),
  Endpoint.new("/admin/status", "DELETE", [] of Param),
  Endpoint.new("/admin/status", "PATCH", [] of Param),
  Endpoint.new("/admin/status", "HEAD", [] of Param),
  Endpoint.new("/admin/status", "OPTIONS", [] of Param),
]

FunctionalTester.new("fixtures/typescript/nestjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
