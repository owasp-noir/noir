require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1", "GET"),
  Endpoint.new("/admin", "GET"),
  Endpoint.new("/foo", "GET"),
  Endpoint.new("/bar", "GET"),
  Endpoint.new("/compose", "DELETE"),
  Endpoint.new("/ing", "POST"),
  Endpoint.new("/toml", "PUT"),
]

FunctionalTester.new("fixtures/specification/traefik/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
