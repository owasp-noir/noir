require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/hr/users/*", "GET"),
  Endpoint.new("/v1/hr/users", "POST"),
  # JavaRegex anchors are stripped; no verb condition means any verb.
  Endpoint.new("/v1/hr/reports/[0-9]+", "ANY"),
  Endpoint.new("/v1/hr/exports/**", "ANY"),
  Endpoint.new("/v1/hr/items/*", "GET"),
  # Each `or` branch keeps its own verb: no `POST /a` or `GET /b`.
  Endpoint.new("/v1/hr/a", "GET"),
  Endpoint.new("/v1/hr/b", "POST"),
  # A negated path clause is not a route; only the verb applies.
  Endpoint.new("/v1/hr", "PATCH"),
  # A proxy endpoint without conditional flows exposes its whole base path.
  Endpoint.new("/health", "ANY"),
]

FunctionalTester.new("fixtures/specification/apigee/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
