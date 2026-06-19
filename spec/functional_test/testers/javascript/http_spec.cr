require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/users", "GET", [
    Param.new("x-api-key", "", "header"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/users/settings", "PUT", [
    Param.new("x-trace-id", "", "header"),
  ]),
  Endpoint.new("/api/users/archive", "DELETE"),
  Endpoint.new("/api/reports", "GET", [
    Param.new("period", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/javascript/http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
