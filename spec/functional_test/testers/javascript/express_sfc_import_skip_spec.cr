require "../../func_spec.cr"

# A file that imports a `.vue` (or `.svelte`) Single-File Component is
# frontend by construction — its wrapped-API-client calls
# (`api.patch('/collections/x', {...})`) are outbound requests, not route
# registrations. Only the real Express route survives.
expected_endpoints = [
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_sfc_import_skip/", {
  :techs     => 1,
  :endpoints => 1,
}, expected_endpoints).perform_tests
