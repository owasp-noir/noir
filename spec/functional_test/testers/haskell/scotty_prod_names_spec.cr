require "../../func_spec.cr"

# A `Spec` / `Test` / `Tests` module name is not a test by itself:
# `OpenApiSpec.hs` (the OpenAPI document), `SpeedTest.hs` (a speed-test
# endpoint) and `Handlers/Tests.hs` (a quiz backend) serve real routes. The
# same suffixes on a file that imports Test.Hspec / Test.Tasty, and anything
# under test/, still mark test code.
expected_endpoints = [
  Endpoint.new("/openapi.json", "GET"),
  Endpoint.new("/speedtest", "GET"),
  Endpoint.new("/tests", "GET"),
]

FunctionalTester.new("fixtures/haskell/scotty_prod_names/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
