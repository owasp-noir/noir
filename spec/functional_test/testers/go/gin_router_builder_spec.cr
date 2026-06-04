require "../../func_spec.cr"

# The canonical gin layout splits route registration across
# `func addXRoutes(rg *gin.RouterGroup)` helpers called from a central
# function with a versioned group. The prefix (`/v1`) lives at the call
# site, not in the helper, and the helper's parameter name (`rg`) does
# NOT match the caller's group variable (`v1`) — so the helper's routes
# need the call-site prefix grafted on. addPingRoutes is reused under
# both /v1 and /v2, so it must yield a route for each.
expected_endpoints = [
  Endpoint.new("/v1/users/", "GET"),
  Endpoint.new("/v1/users/", "POST"),
  Endpoint.new("/v1/users/comments", "GET"),
  Endpoint.new("/v1/ping/", "GET"),
  Endpoint.new("/v2/ping/", "GET"),
]

FunctionalTester.new("fixtures/go/gin_router_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
