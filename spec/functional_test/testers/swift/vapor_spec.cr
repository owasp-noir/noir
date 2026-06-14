require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/v2/ping", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:userID", "GET"),
  Endpoint.new("/users/:userID/posts/:postID", "PUT"),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/api/login", "POST"),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/users/:id", "DELETE"),
  Endpoint.new("/articles/:articleID", "PATCH"),
  Endpoint.new("/status", "GET"),
  # RoutesBuilder extension: bare `grouped(...)` + `self.<verb>` (AdminRoutes).
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/purge", "POST"),
]

FunctionalTester.new("fixtures/swift/vapor/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
