require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/v1/x", "GET"),
  Endpoint.new("/a/y", "GET"),
]

FunctionalTester.new("fixtures/go/fiber_self_regroup/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
