require "../../func_spec.cr"

expected_endpoints = [
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
  Endpoint.new("/users/search", "GET", [
    Param.new("query", "", "query"),
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("order", "", "query"),
    Param.new("User-Agent", "", "header"),
    Param.new("X-Custom", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
    Param.new("name", "", "json"),
    Param.new("age", "", "json"),
    Param.new("Content-Type", "", "header"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/users/:id/profile", "GET", [
    Param.new("id", "", "path"),
    Param.new("session_token", "", "cookie"),
    Param.new("If-None-Match", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/ruby/hanami/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
