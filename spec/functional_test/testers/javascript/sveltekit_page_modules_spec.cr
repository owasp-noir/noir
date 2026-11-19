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

tester = FunctionalTester.new("fixtures/javascript/sveltekit_page_modules/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports the page module's `load` line", tags: "functional" do
  roadmap = tester.endpoints.find! { |endpoint| endpoint.url == "/roadmap" && endpoint.method == "GET" }
  roadmap.details.code_paths.first.line.should eq(2)
end
