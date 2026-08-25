require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/before", "ANY"),
  Endpoint.new("^/after/(.*)", "ANY"),
  Endpoint.new("/fallback", "ANY"),
  Endpoint.new("/old", "ANY"),
  Endpoint.new("^/legacy/(.*)", "ANY"),
  Endpoint.new("/(.*)", "ANY"),
]

FunctionalTester.new("fixtures/specification/vercel/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
