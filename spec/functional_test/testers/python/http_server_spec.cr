require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/submit", "POST", [
    Param.new("name", "", "form"),
    Param.new("id", "", "json"),
    Param.new("X-Token", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/delete-me", "DELETE"),
]

FunctionalTester.new("fixtures/python/http_server/", {
  :techs     => 1,
  :endpoints => 5,
}, expected_endpoints).perform_tests
