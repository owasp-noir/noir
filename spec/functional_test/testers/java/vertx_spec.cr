require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/:id", "PUT"),
  Endpoint.new("/api/users/:id", "DELETE"),
  Endpoint.new("/api/users/:id", "PATCH"),
  Endpoint.new("/api/status", "HEAD"),
  Endpoint.new("/api/options", "OPTIONS"),
  Endpoint.new("/api/products/:category", "GET"),
  Endpoint.new("/orders/:id", "GET"),
  Endpoint.new("/orders", "POST"),
  Endpoint.new("/orders/:id", "PUT"),
  Endpoint.new("/v1/items", "GET"),
  Endpoint.new("/v1/items", "POST"),
  Endpoint.new("/api", "GET"),
]

FunctionalTester.new("fixtures/java/vertx/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
