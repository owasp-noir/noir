require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/features", "GET"),
  Endpoint.new("/features", "POST"),
]

FunctionalTester.new("fixtures/go/gin_importless_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
