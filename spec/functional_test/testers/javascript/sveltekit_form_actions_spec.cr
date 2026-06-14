require "../../func_spec.cr"

# `+page.server.ts` form actions register an inbound POST at the page URL
# (distinct from the `+page.svelte` GET). And an optional-with-matcher
# segment `[[assetId=id]]` normalizes to `{assetId}`, not a literal.
expected_endpoints = [
  Endpoint.new("/login", "GET"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/photos/{assetId}", "GET", [Param.new("assetId", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/sveltekit_form_actions/", {
  :techs     => 1,
  :endpoints => 3,
}, expected_endpoints).perform_tests
