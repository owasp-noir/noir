require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/<id>", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/items/<id>", "PUT"),
]

FunctionalTester.new("fixtures/rust/salvo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
