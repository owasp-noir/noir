require "../../func_spec.cr"

# #3309: a route with only `+page.js` / `+page.server.ts` (a redirecting
# `load`) still answers GET.
expected_endpoints = [
  Endpoint.new("/about", "GET"),
  Endpoint.new("/roadmap", "GET"),
  Endpoint.new("/e/{code}", "GET", [Param.new("code", "", "path")]),
  # `+page@desktop.svelte` is the page, so `+page.js` does not add a second GET.
  Endpoint.new("/news", "GET"),
]

FunctionalTester.new("fixtures/javascript/sveltekit_page_modules/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
