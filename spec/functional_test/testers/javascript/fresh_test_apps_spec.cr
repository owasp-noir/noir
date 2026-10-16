require "../../func_spec.cr"

# Fresh ignores `*.test.ts` / `*_test.tsx` under `routes/` (its own
# TEST_FILE_PATTERN), and `new App()` inside a `*_test.tsx` or under
# `tests/` is a harness, not the served app. `routes/test.tsx` is a page.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/test", "GET"),
  Endpoint.new("/ping", "GET"),
]

FunctionalTester.new("fixtures/javascript/fresh_test_apps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
