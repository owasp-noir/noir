require "../../func_spec.cr"

# A lab suite under test/ registers routes on a throwaway server driven by
# `server.inject`; it is not served. `src/proxy.js` imports axios beside hapi
# and keeps its route (the import-blind test check, not the library-marker one).
expected_endpoints = [
  Endpoint.new("/hapi-real", "GET"),
  Endpoint.new("/hapi-proxy", "GET"),
]

FunctionalTester.new("fixtures/javascript/hapi_test_suite/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
