require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/greetings", "GET", [
    Param.new("page", "", "query"),
    Param.new("size", "", "query"),
  ]),
  Endpoint.new("/greetings/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/greetings", "POST", [
    Param.new("message", "", "json"),
    Param.new("locale", "", "json"),
  ]),
  Endpoint.new("/greetings/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("pwd", "", "form"),
  ]),
  Endpoint.new("/greetings/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("message", "", "json"),
    Param.new("locale", "", "json"),
  ]),
  Endpoint.new("/greetings/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/java/quarkus/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
