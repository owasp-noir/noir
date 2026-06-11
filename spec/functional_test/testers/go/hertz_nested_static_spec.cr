require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/static/ok.txt", "GET"),
]

FunctionalTester.new("fixtures/go/hertz_nested_static/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
