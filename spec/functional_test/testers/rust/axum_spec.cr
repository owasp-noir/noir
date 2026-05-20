require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/foo", "GET"),
  Endpoint.new("/bar", "POST"),
  Endpoint.new("/ws", "ANY"),
  Endpoint.new("/favicon.ico", "ANY"),
  Endpoint.new("/assets/*", "ANY"),
  Endpoint.new("/*", "ANY"),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/admin", "POST"),
]

FunctionalTester.new("fixtures/rust/axum/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
