require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/orders", "GET"),
  Endpoint.new("/orders", "POST"),
]

FunctionalTester.new("fixtures/ruby/grape/", {
  :techs     => 1,
  :endpoints => 7,
}, expected_endpoints).perform_tests
