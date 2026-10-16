require "../../func_spec.cr"

# `test/fixture/` is a mini Nitro project the framework's suite spins up,
# for both `routes/` and `api/`. The real project's routes stay.
expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/api/e2e", "GET"),
]

FunctionalTester.new("fixtures/javascript/nitro_test_apps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
