require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("page", "0", "query"),
    Param.new("size", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "", "json"),
  ]),
  Endpoint.new("/users/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("active", "", "query"),
    Param.new("role", "", "query"),
    Param.new("X-Tenant", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/java/jaxrs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
