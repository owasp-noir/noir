require "../../func_spec.cr"

# A repo with BOTH an Express app (app.js) and a Hono handler file
# (service.ts) that uses the same `.get()/.post()` chaining shape
# Express's shared `Noir::JSRouteExtractor` recognizes, but never mentions
# express. The Express analyzer must not claim it (mislabeling its routes
# js_express); the Hono analyzer owns it (#2368).
expected_endpoints = [
  Endpoint.new("/express-home", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/hono-items", "GET"),
  Endpoint.new("/hono-items", "POST"),
]

tester = FunctionalTester.new("fixtures/javascript/express_hono_foreign/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "tags Hono handler-file routes js_hono, not js_express" do
  hono_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/hono-items" && endpoint.method == "POST" }
  hono_route.should_not be_nil
  hono_route.try(&.details.technology).should eq("js_hono")
end

it "still tags Express's own routes js_express" do
  express_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/express-home" && endpoint.method == "GET" }
  express_route.should_not be_nil
  express_route.try(&.details.technology).should eq("js_express")
end
