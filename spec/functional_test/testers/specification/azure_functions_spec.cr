require "../../func_spec.cr"

# The Functions host serves HTTP triggers under a route prefix: `api` unless
# `host.json` overrides it. `CreateUser`/`ListUsers` have no `host.json` and so
# take the host default; `custom-prefix` sets `routePrefix: gateway`.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/gateway/ping", "GET"),
]

FunctionalTester.new("fixtures/specification/azure_functions/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
