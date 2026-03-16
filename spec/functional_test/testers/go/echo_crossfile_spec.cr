require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/v2/data", "POST", [
    Param.new("payload", "", "form"),
  ]),
  Endpoint.new("/api/v2/items", "GET"),
]

FunctionalTester.new("fixtures/go/echo_crossfile/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
