require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/after-heredoc", "GET"),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
    Param.new("page", "", "query"),
    Param.new("X-API-KEY", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/crystal/http/", {
  :techs     => 1,
  :endpoints => 5,
}, expected_endpoints).perform_tests
