require "../../func_spec.cr"

# A rule without `matches` matches every path.
expected_endpoints = [
  Endpoint.new("/login", "ANY"),
  Endpoint.new("/", "ANY"),
]

FunctionalTester.new("fixtures/specification/k8s_gateway_api_catchall/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
