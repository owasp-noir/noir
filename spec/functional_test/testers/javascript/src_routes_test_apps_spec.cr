require "../../func_spec.cr"

# SolidStart and Qwik City share `src/routes/`. Sample apps under
# `tests/fixtures/` (with their own manifest, or none beside `src`) are the
# framework suite's, not served routes.
expected_endpoints = [
  Endpoint.new("/pricing", "GET"),
  Endpoint.new("/team", "GET"),
]

FunctionalTester.new("fixtures/javascript/src_routes_test_apps/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
