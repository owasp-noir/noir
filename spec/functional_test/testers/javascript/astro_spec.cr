require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/{slug}", "GET", [
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # No explicit verb exports → falls back to GET / POST / PUT / DELETE / PATCH.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/health", "POST"),
  Endpoint.new("/api/health", "PUT"),
  Endpoint.new("/api/health", "DELETE"),
  Endpoint.new("/api/health", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/astro/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
