require "../../func_spec.cr"

extected_endpoints = [
  # Traditional server routes
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
  # Route with path parameter
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-api-key", "", "header"),
  ]),
  # Route with base path from applyRoutes
  Endpoint.new("/api/v1/products", "GET", [
    Param.new("limit", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/javascript/restify/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
