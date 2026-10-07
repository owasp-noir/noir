require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  # `routeAction$` posts back to the page; `(auth)` is hidden.
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/docs/{rest}", "GET", [Param.new("rest", "", "path")]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  # `onRequest` alone answers every verb.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/health", "POST"),
  Endpoint.new("/api/health", "PUT"),
  Endpoint.new("/api/health", "DELETE"),
  Endpoint.new("/api/health", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/qwik_city/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
