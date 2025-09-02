require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/profile", "PUT"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/login", "POST"),
]

FunctionalTester.new("fixtures/go/gozero/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
