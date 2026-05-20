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
  ]),
  Endpoint.new("/users/:userId", "PATCH", [
    Param.new("userId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/hono_on_array/", {
  :techs => 1,
}, expected_endpoints).perform_tests
