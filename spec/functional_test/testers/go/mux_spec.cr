require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("auth_token", "", "cookie"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "query"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/{id}/posts/{postid}", "GET", [
    Param.new("id", "", "path"),
    Param.new("postid", "", "path"),
  ]),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/health", "GET"),
  Endpoint.new("/static/test.txt", "GET"),
]

FunctionalTester.new("fixtures/go/mux/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
