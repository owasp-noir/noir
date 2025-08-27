require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/products/:category/:id", "GET", [
    Param.new("category", "", "path"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/v1/status", "GET"),
]

FunctionalTester.new("fixtures/rust/tide/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
