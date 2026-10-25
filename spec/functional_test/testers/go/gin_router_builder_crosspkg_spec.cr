require "../../func_spec.cr"

# Router builders called from another package (`routes.RegisterUsers(api)`)
# take the caller's group prefix, and an inline sub-group argument
# (`addHealth(api.Group("/health"))`) keeps its receiver's prefix too.
expected_endpoints = [
  Endpoint.new("/api/v1/users/:id", "GET"),
  Endpoint.new("/api/v1/users", "POST"),
  Endpoint.new("/api/v1/posts/:slug", "GET"),
  Endpoint.new("/api/v1/health/live", "GET"),
]

FunctionalTester.new("fixtures/go/gin_router_builder_crosspkg/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
