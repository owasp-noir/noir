require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/orders", "GET"),
]

FunctionalTester.new("fixtures/specification/aws_cloudformation/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
