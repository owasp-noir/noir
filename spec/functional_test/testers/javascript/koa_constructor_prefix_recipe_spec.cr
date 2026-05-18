require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/v2/users", "GET"),
  Endpoint.new("/api/v2/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/koa_constructor_prefix_recipe/", {
  :techs => 1,
}, expected_endpoints).perform_tests
