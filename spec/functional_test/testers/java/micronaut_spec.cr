require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/books", "GET", [
    Param.new("page", "", "query"),
    Param.new("size", "", "query"),
  ]),
  Endpoint.new("/books/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace", "", "header"),
  ]),
  Endpoint.new("/books/popular", "GET"),
  Endpoint.new("/books/featured", "GET"),
  Endpoint.new("/books", "POST", [
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("year", "", "json"),
  ]),
  Endpoint.new("/books/login", "POST", [
    Param.new("username", "", "query"),
    Param.new("pwd", "", "query"),
  ]),
  Endpoint.new("/books/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("year", "", "json"),
  ]),
  Endpoint.new("/books/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/books/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("year", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/java/micronaut/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
