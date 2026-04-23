require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("role", "", "form"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("session", "", "cookie"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
  ]),
  Endpoint.new("/profile", "PUT", [
    Param.new("bio", "", "form"),
  ]),
  Endpoint.new("/search/{category}", "GET", [
    Param.new("category", "", "path"),
    Param.new("q", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/aiohttp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
