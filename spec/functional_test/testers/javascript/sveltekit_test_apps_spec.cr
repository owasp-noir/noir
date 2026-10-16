require "../../func_spec.cr"

# A framework's own repo keeps sample apps under `test/` (each with its own
# svelte.config.js), and docs sites keep tutorial overlays nested below the
# real app. Neither serves traffic. `src/routes/test/` and `api/e2e/` are
# real URLs and stay.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/test", "GET"),
  Endpoint.new("/api/e2e", "GET"),
]

FunctionalTester.new("fixtures/javascript/sveltekit_test_apps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
