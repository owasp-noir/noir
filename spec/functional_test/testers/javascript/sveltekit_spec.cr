require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/new", "GET"),
  # `(marketing)` is a route group — stripped from the URL.
  Endpoint.new("/about", "GET"),
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
  # Fallback: no explicit verb exports → GET / POST / PUT / DELETE / PATCH.
  Endpoint.new("/api/auth", "GET"),
  Endpoint.new("/api/auth", "POST"),
  Endpoint.new("/api/auth", "PUT"),
  Endpoint.new("/api/auth", "DELETE"),
  Endpoint.new("/api/auth", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/sveltekit/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
