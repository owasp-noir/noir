require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_shallow_root/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
