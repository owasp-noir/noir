require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/{id}", "GET"),
  Endpoint.new("/users/{id}", "DELETE"),
  Endpoint.new("/me", "GET"),
]

FunctionalTester.new("fixtures/specification/aws_cdk/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
