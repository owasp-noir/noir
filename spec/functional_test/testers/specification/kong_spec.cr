require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users", "POST"),
  Endpoint.new("/~/admin/.*", "ANY"),
  Endpoint.new("/v1/orders", "GET"),
  Endpoint.new("/v1/orders", "POST"),
]

FunctionalTester.new("fixtures/specification/kong/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
