require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/hr/users/*", "GET"),
  Endpoint.new("/v1/hr/users", "POST"),
  # JavaRegex anchors are stripped; no verb condition means any verb.
  Endpoint.new("/v1/hr/reports/[0-9]+", "ANY"),
  Endpoint.new("/v1/hr/exports/**", "ANY"),
  # A proxy endpoint without conditional flows exposes its whole base path.
  Endpoint.new("/health", "ANY"),
]

FunctionalTester.new("fixtures/specification/apigee/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
