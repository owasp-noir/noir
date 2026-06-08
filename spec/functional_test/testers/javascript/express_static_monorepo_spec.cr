require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/assets/app-only.txt", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_static_monorepo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
