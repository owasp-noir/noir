require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/api/products/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/items/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/api/profiles/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/health", "HEAD"),
  Endpoint.new("/api/config", "OPTIONS"),
]

FunctionalTester.new("fixtures/rust/gotham/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
