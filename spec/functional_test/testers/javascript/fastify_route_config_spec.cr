require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/single", "GET"),
  Endpoint.new("/items/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/items/:id", "POST", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:userId", "PUT", [
    Param.new("userId", "", "path"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/users/:userId", "PATCH", [
    Param.new("userId", "", "path"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/regression", "GET"),
]

FunctionalTester.new("fixtures/javascript/fastify_route_config/", {
  :techs => 1,
}, expected_endpoints).perform_tests
