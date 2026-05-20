require "../../func_spec.cr"

expected_endpoints = [
  # Cascade-style registrations on the root router.
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),

  # `..all('/echo', ...)` fans out to every standard verb.
  Endpoint.new("/echo", "GET"),
  Endpoint.new("/echo", "POST"),
  Endpoint.new("/echo", "PUT"),
  Endpoint.new("/echo", "PATCH"),
  Endpoint.new("/echo", "DELETE"),
  Endpoint.new("/echo", "HEAD"),
  Endpoint.new("/echo", "OPTIONS"),

  # `apiRouter` is mounted at `/api/v1/` on the root router. The
  # regex constraint inside `<itemId|[0-9]+>` is stripped from the
  # surfaced path param.
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/api/v1/items/{itemId}", "GET", [Param.new("itemId", "", "path")]),
  # Direct `apiRouter.patch(...)` outside the cascade.
  Endpoint.new("/api/v1/items/{itemId}", "PATCH", [Param.new("itemId", "", "path")]),
]

FunctionalTester.new("fixtures/dart/shelf/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
