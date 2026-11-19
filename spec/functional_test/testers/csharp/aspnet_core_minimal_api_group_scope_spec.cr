require "../../func_spec.cr"

# Two extension methods in one file that each declare `var group`, and a
# `this RouteGroupBuilder group` parameter beside them: every `group` is the
# one of its own method. A top-level local function sees the top-level group.
expected_endpoints = [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/orders", "GET"),
  Endpoint.new("/api/orders", "POST"),
  Endpoint.new("/api/v1/products", "GET"),
  Endpoint.new("/api/v1/products/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/shared/ping", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api_group_scope/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
