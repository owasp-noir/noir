require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "ANY"),
  Endpoint.new("/admin", "ANY"),
  Endpoint.new("/metrics", "ANY"),
]

FunctionalTester.new("fixtures/specification/k8s_ingress/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
