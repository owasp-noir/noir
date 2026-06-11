require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/features", "GET"),
  Endpoint.new("/features", "POST"),
  Endpoint.new("/features/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/go/hertz_importless_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
