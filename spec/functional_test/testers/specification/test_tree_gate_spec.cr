require "../../func_spec.cr"

# Spec and config documents under test trees are test input, not the
# project's surface. The root OpenAPI document, an ingress under `deploy/test`
# (a real test environment) and a client collection under `tests/` stay; the
# OpenAPI documents under `tests/` and `Billing.UnitTests/`, the gateway config
# under `src/test/`, the ingress under `testdata/` and the Visual Studio
# `Service References` proxy are dropped.
expected_endpoints = [
  Endpoint.new("/pets", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/test-env", "ANY"),
]

FunctionalTester.new("fixtures/specification/test_tree_gate/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
