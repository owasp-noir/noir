require "../../func_spec.cr"

extected_endpoints = [
  # Traditional app-based routes
  Endpoint.new("/", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/upload", "POST", [
    Param.new("name", "", "json"),
    Param.new("auth", "", "cookie"),
  ]),
  # Router-based routes
  Endpoint.new("/api", "GET", [
    Param.new("page", "", "query"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/api/submit", "POST", [
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
    Param.new("sessionId", "", "cookie"),
  ]),
  # ES6 import style router
  Endpoint.new("/users", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-api-key", "", "header"),
  ]),
  # Route with path parameter
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
