require "../../func_spec.cr"

# Astro's own repo parks sample projects under `test/fixtures/` and `e2e/`.
# A page named `test` in the real project is still a route.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/test", "GET"),
]

FunctionalTester.new("fixtures/javascript/astro_test_apps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
