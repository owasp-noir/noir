require "../../func_spec.cr"

# #3266: a router returned by an imported factory (`const items =
# initItemsRouter()`, named or default export) keeps its mount prefix.
expected_endpoints = [
  Endpoint.new("/api/items/list", "GET"),
  Endpoint.new("/api/users/me", "GET"),
]

FunctionalTester.new("fixtures/javascript/koa_factory_router_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
