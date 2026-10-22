require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("body", "", "json"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/api/health", "GET", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("title", "", "form"),
  ]),
  Endpoint.new("/search", "QUERY", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/query-manual", "QUERY", [
    Param.new("filter", "", "query"),
  ]),
  # server.go: a sub-mux route; `http.Handle("/v2/", api)` is its mount, not a route
  Endpoint.new("/v2/ping", "GET"),
]

FunctionalTester.new("fixtures/go/http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
