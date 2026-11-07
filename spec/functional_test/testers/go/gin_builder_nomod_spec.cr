require "../../func_spec.cr"

# No go.mod. `controllers.RegisterProductRoutes(api.Group("/products"))`
# still has to keep both the `/api` group and the inline `/products`
# segment. With a module file the same shape is gin_router_builder_crosspkg.
expected_endpoints = [
  Endpoint.new("/api/products/", "GET"),
  Endpoint.new("/api/products/:slug", "GET"),
]

FunctionalTester.new("fixtures/go/gin_builder_nomod/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
