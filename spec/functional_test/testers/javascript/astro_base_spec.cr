require "../../func_spec.cr"

# `base: '/docs'` in astro.config.mjs prefixes every route; the root page is
# the bare base. `proxy.ts` exports `GET` and `ALL`: `ALL` answers the other
# methods.
expected_endpoints = [
  Endpoint.new("/docs", "GET"),
  Endpoint.new("/docs/api/search", "GET"),
] + %w[GET POST PUT DELETE PATCH].map { |method| Endpoint.new("/docs/api/proxy", method) }

tester = FunctionalTester.new("fixtures/javascript/astro_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports the `ALL` export's line for the methods it answers", tags: "functional" do
  proxy = ->(method : String) { tester.endpoints.find! { |endpoint| endpoint.url == "/docs/api/proxy" && endpoint.method == method } }
  proxy.call("GET").details.code_paths.first.line.should eq(3)
  proxy.call("POST").details.code_paths.first.line.should eq(5)
end
