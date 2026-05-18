require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/cors", "OPTIONS"),
  Endpoint.new("/ping", "HEAD"),
]

FunctionalTester.new("fixtures/go/chi_http_methods/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
