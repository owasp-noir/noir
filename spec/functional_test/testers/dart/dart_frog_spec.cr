require "../../func_spec.cr"

expected_endpoints = [
  # Plain `onRequest` with no `HttpMethod.*` references → fall back
  # to the standard verb set (GET / POST / PUT / DELETE / PATCH).
  Endpoint.new("/", "GET"),
  Endpoint.new("/", "POST"),
  Endpoint.new("/", "PUT"),
  Endpoint.new("/", "DELETE"),
  Endpoint.new("/", "PATCH"),
  # `about.dart` only references `HttpMethod.get`.
  Endpoint.new("/about", "GET"),
  # `users/index.dart` switches on get / post.
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  # `users/[id].dart` references get / put / delete.
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  # Nested under `[id]`.
  Endpoint.new("/users/{id}/posts", "GET", [Param.new("id", "", "path")]),
  # `api/health.dart` is the catch-all fallback again.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/health", "POST"),
  Endpoint.new("/api/health", "PUT"),
  Endpoint.new("/api/health", "DELETE"),
  Endpoint.new("/api/health", "PATCH"),
]

FunctionalTester.new("fixtures/dart/dart_frog/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
