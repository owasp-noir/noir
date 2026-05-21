require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/*", "ANY"),
  Endpoint.new("/admin/*", "ANY"),
  Endpoint.new("/api/*", "GET"),
  Endpoint.new("/api/*", "POST"),
  Endpoint.new("/old", "ANY"),
]

FunctionalTester.new("fixtures/specification/caddy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
