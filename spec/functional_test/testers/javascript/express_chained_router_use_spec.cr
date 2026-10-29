require "../../func_spec.cr"

# #3291: `.use(` links on an anonymous `Router()` chain (`const api =
# Router().use(items)`, `export default Router().use('/api', api)`) keep
# their mount prefix.
expected_endpoints = [
  Endpoint.new("/api/items", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_chained_router_use/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
