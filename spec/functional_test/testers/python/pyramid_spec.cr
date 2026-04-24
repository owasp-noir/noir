require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("q", "", "query"),
    Param.new("lang", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Token", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/api/items", "POST", [
    Param.new("name", "", "form"),
    Param.new("price", "", "form"),
  ]),
  Endpoint.new("/api/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
  ]),
  Endpoint.new("/ping", "GET", [
    Param.new("format", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/pyramid/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
