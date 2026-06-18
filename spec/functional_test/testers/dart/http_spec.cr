require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/health", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/profiles", "PATCH", [
    Param.new("X-Profile-Mode", "", "header"),
  ]),
  Endpoint.new("/files", "GET"),
  Endpoint.new("/reports", "DELETE"),
  Endpoint.new("/status", "GET"),
]

FunctionalTester.new("fixtures/dart/http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
