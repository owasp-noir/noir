require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/dev/users", "GET"),
  Endpoint.new("/dev/users", "POST"),
  Endpoint.new("/dev/users/{id}", "GET"),
  Endpoint.new("/dev/health", "GET"),
]

FunctionalTester.new("fixtures/specification/serverless_framework/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
