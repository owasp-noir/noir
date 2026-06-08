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
  # Decorators between the route decorator and method should not hide
  # method params or request-object usage.
  Endpoint.new("/admin/reports/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("include", "", "query"),
    Param.new("x-token", "", "header"),
  ]),
  # FileInterceptor field names are the actual upload body surface.
  Endpoint.new("/admin/upload", "POST", [
    Param.new("avatar", "", "body"),
    Param.new("file", "", "body"),
  ]),
  # Method-level URI versioning.
  Endpoint.new("/v2/admin/versioned", "GET"),
  # NestJS can serve Express static middleware from the bootstrap file.
  Endpoint.new("/static/logo.txt", "GET"),
]

FunctionalTester.new("fixtures/javascript/nestjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
