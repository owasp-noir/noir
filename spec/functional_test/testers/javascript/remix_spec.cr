require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  # `_auth.login.tsx` — pathless layout `_auth` strips from URL.
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/login", "PUT"),
  Endpoint.new("/login", "PATCH"),
  Endpoint.new("/login", "DELETE"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users", "PUT"),
  Endpoint.new("/api/users", "PATCH"),
  Endpoint.new("/api/users", "DELETE"),
  Endpoint.new("/{splat}", "GET", [Param.new("splat", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/remix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
