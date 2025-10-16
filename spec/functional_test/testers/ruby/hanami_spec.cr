require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/books", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/books/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("Authorization", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/books/new", "GET"),
  Endpoint.new("/books", "POST", [
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("isbn", "", "json"),
    Param.new("Content-Type", "", "header"),
    Param.new("user_token", "", "cookie"),
  ]),
  Endpoint.new("/books/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("title", "", "json"),
    Param.new("author", "", "json"),
    Param.new("If-Match", "", "header"),
  ]),
  Endpoint.new("/books/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("csrf_token", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/ruby/hanami/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
