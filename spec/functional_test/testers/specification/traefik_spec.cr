require "../../func_spec.cr"

# A rule with no `Method()` matcher matches every verb, so it is `ANY`.
expected_endpoints = [
  Endpoint.new("/v1", "ANY"),
  Endpoint.new("/admin", "GET"),
  Endpoint.new("/foo", "ANY"),
  Endpoint.new("/bar", "ANY"),
  Endpoint.new("/compose", "DELETE"),
  Endpoint.new("/ing", "POST"),
  Endpoint.new("/toml", "PUT"),
]

FunctionalTester.new("fixtures/specification/traefik/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
