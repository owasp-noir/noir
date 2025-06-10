require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/info", "GET"),
  Endpoint.new("/settings", "GET"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/simple", "GET"),
  Endpoint.new("/items/:itemId", "DELETE", [
    Param.new("itemId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/koa/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
