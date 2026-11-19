require "../../func_spec.cr"

# `+page@.svelte` is a page; `[[lang]]` serves the URL with and without the
# segment; `[x+2e]` is an escaped `.`; `fallback` answers the methods the
# file exports no handler for.
expected_endpoints = [
  Endpoint.new("/checkout", "GET"),
  Endpoint.new("/control", "GET"),
  Endpoint.new("/pricing", "GET"),
  Endpoint.new("/{lang}/pricing", "GET", [Param.new("lang", "", "path")]),
  Endpoint.new("/.well-known/security.txt", "GET"),
] + %w[GET POST PUT DELETE PATCH].map { |method| Endpoint.new("/api/proxy", method) }

tester = FunctionalTester.new("fixtures/javascript/sveltekit_conventions/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports the `fallback` export's line for the methods it answers", tags: "functional" do
  proxy = ->(method : String) { tester.endpoints.find! { |endpoint| endpoint.url == "/api/proxy" && endpoint.method == method } }
  proxy.call("GET").details.code_paths.first.line.should eq(3)
  proxy.call("DELETE").details.code_paths.first.line.should eq(7)
end
