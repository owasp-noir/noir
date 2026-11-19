require "../../func_spec.cr"

# A router builder handed a group built off another builder's parameter
# (`orders := rg.Group("/orders"); registerOrders(orders)`, or inline
# `user.RegisterRoutes(rg.Group("/users"))`) takes the outer builder's
# call-site prefix as well.
expected_endpoints = [
  Endpoint.new("/api/v1/ping", "GET"),
  Endpoint.new("/api/v1/misc", "GET"),
  Endpoint.new("/api/v1/orders", "GET"),
  Endpoint.new("/api/v1/orders/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users", "POST"),
  Endpoint.new("/api/v1/users/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/go/gin_nested_builder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
