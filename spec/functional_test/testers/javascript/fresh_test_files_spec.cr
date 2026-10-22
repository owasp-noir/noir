require "../../func_spec.cr"

# Fresh never serves `[._]test.<ext>` files under routes/ (its own default
# `ignore`), and a `new App()` built inside a `Deno.test` closure in
# `tests/context_test.tsx` is driven in-process, not served.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/real-app", "GET"),
]

FunctionalTester.new("fixtures/javascript/fresh_test_files/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
