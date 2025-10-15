require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/products/:category/:id", "GET", [
    Param.new("category", "", "path"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/search", "GET", [
    Param.new("SearchQuery", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("UserData", "", "json"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("LoginForm", "", "form"),
  ]),
  Endpoint.new("/auth", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/session", "GET", [
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/complex/:id", "POST", [
    Param.new("id", "", "path"),
    Param.new("SearchQuery", "", "query"),
    Param.new("UserData", "", "json"),
    Param.new("Authorization", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/rust/tide/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
