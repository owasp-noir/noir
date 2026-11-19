require "../../func_spec.cr"

# A router builder whose group parameter is typed `gin.IRouter` or
# `gin.IRoutes` takes its call-site prefix like a `*gin.RouterGroup` one.
# One that is also handed the engine is read once, as written.
expected_endpoints = [
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/orders", "GET"),
  Endpoint.new("/api/v1/orders/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/orders/:id/items", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/healthz", "GET"),
  Endpoint.new("/shared", "GET"),
]

FunctionalTester.new("fixtures/go/gin_builder_interface/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
