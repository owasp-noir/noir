require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "ANY"),
  Endpoint.new("/admin/.*", "ANY"),
  Endpoint.new("/healthz", "ANY"),
  Endpoint.new("/api/", "ANY"),
  Endpoint.new("/api/", "POST"),
]

FunctionalTester.new("fixtures/specification/nginx/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
