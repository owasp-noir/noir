require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
    Param.new("User-Agent", "", "header"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("username", "", "form"),
    Param.new("email", "", "form"),
    Param.new("password", "", "form"),
    Param.new("role", "", "form"),
    Param.new("Content-Type", "", "header"),
    Param.new("X-Client-ID", "", "header"),
  ]),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
    Param.new("Accept-Language", "", "header"),
  ]),
  Endpoint.new("/products/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "form"),
    Param.new("price", "", "form"),
    Param.new("X-Vendor-ID", "", "header"),
  ]),
  Endpoint.new("/products/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("X-Admin-Key", "", "header"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("session_id", "", "cookie"),
    Param.new("admin_token", "", "cookie"),
    Param.new("action", "", "query"),
    Param.new("X-Admin-Key", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/go/fasthttp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
