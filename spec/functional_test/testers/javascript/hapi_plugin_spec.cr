require "../../func_spec.cr"

# Plugin modules never import hapi; the project's package.json puts them in
# scope, and `register(..., { routes: { prefix } })` serves them under it.
expected_endpoints = [
  Endpoint.new("/api/users", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/api/users/{userId}", "GET", [Param.new("userId", "", "path")]),
  Endpoint.new("/api/orders/{orderId}", "DELETE", [Param.new("orderId", "", "path")]),
  Endpoint.new("/items/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/hapi_plugin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
