require "../../func_spec.cr"

# A repo holding BOTH an Express app and a koa-router app whose routes are
# aggregated in one file and mounted under `/api` from another.
#
# Express and Hono each run a `RouterMountScanner` over *every* JS/TS file in
# the tree, and both write the prefixes they resolve into the one process-wide
# `CodeLocator` table that `Noir::JSRouteExtractor` reads back per file. The
# koa aggregator's prefix-less `api.use(users)` reads to that scanner as a
# mount at `/`, so `users-router.js` ended up carrying two prefixes — koa's
# real `/api` and Express's invented `/` — and every koa route was reported a
# second time at a bare path the application does not serve.
#
# Which of the two won was down to fiber scheduling between the concurrently
# running Express and Hono scanners, so the phantom endpoints came and went
# between runs of the same scan.
expected_endpoints = [
  Endpoint.new("/express-home", "GET"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/login", "POST"),
]

tester = FunctionalTester.new("fixtures/javascript/express_koa_foreign_mount/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not report koa routes at the un-prefixed path" do
  phantom = tester.app.endpoints.select { |endpoint| endpoint.url == "/users" || endpoint.url == "/users/login" }
  phantom.should be_empty
end

it "keeps the koa mount prefix on the koa analyzer's endpoints" do
  koa_route = tester.app.endpoints.find { |endpoint| endpoint.url == "/api/users" && endpoint.method == "GET" }
  koa_route.should_not be_nil
  koa_route.try(&.details.technology).should eq("js_koa")
end
