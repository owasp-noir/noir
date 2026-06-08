require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/real", "GET"),
]

FunctionalTester.new("fixtures/javascript/nextjs_monorepo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
