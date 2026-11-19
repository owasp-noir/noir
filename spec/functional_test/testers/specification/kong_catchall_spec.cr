require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api", "ANY"),
  # `host-only` (any method) and `method-only` both match every path.
  Endpoint.new("/", "ANY"),
  Endpoint.new("/", "DELETE"),
  Endpoint.new("/top-level", "ANY"),
]

FunctionalTester.new("fixtures/specification/kong_catchall/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
