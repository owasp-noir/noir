require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id/posts/:postid", "GET", [
    Param.new("id", "", "path"),
    Param.new("postid", "", "path"),
  ]),
  Endpoint.new("/items/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/items/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/items/:id/status", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/secure", "GET", [
    Param.new("X-API-Key", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/go/httprouter/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
