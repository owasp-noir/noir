require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/cats", "GET"),
  Endpoint.new("/v1/cats/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/v2/cats", "POST", [
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/v3/cats", "POST", [
    Param.new("body", "", "body"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/v2/dogs/override", "GET"),
]

FunctionalTester.new("fixtures/javascript/nestjs_versioning/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
