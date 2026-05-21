require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users", "POST"),
  Endpoint.new("/v2/.*", "ANY"),
  Endpoint.new("/v1/legacy", "ANY"),
]

FunctionalTester.new("fixtures/specification/k8s_gateway_api/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
