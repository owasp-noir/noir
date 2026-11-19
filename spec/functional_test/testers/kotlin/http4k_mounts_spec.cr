require "../../func_spec.cr"

# Routers bound under a prefix by name (`"/users" bind userRoutes`) or by
# call (`"/orders" bind orderRoutes()`), declared in this file or another,
# serve their routes under that prefix and nowhere else.
expected_endpoints = [
  Endpoint.new("/internal/ping", "GET"),
  Endpoint.new("/inline/x", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/orders", "POST"),
]

FunctionalTester.new("fixtures/kotlin/http4k_mounts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
