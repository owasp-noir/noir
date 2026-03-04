require "../../func_spec.cr"

expected_endpoints = [
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
  Endpoint.new("/multiline", "GET"),
  # handlers.go: PUT method with path variable
  Endpoint.new("/items/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  # handlers.go: DELETE method with path variable
  Endpoint.new("/items/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  # handlers.go: PATCH method with path variable and form param
  Endpoint.new("/items/{id}/status", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("status", "", "query"),
  ]),
  # handlers.go: multiple path variables with query param
  Endpoint.new("/shops/{shopId}/products/{productId}", "GET", [
    Param.new("shopId", "", "path"),
    Param.new("productId", "", "path"),
    Param.new("detail", "", "query"),
  ]),
  # handlers.go: header and cookie extraction
  Endpoint.new("/secure", "GET", [
    Param.new("X-API-Key", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  # handlers.go: nested subrouter
  Endpoint.new("/v2/health", "GET"),
]

FunctionalTester.new("fixtures/go/mux/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
