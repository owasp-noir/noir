require "../../func_spec.cr"

extected_endpoints = [
  # Traditional app-based routes
  Endpoint.new("/", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-API-Key", "", "header"),
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
  # Added endpoints
  Endpoint.new("/products", "GET", [
    Param.new("category", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/profile/:userId", "GET", [
    Param.new("userId", "", "path"),
    Param.new("fields", "", "query"),
  ]),
  Endpoint.new("/v1/status", "GET", [
    Param.new("format", "", "query"),
    Param.new("X-Status-Key", "", "header"),
  ]),
  Endpoint.new("/v1/settings", "PUT", [
    Param.new("theme", "", "json"),
    Param.new("notifications", "", "json"),
    Param.new("userKey", "", "cookie"),
  ]),
  Endpoint.new("/admin/dashboard", "GET", [
    Param.new("view", "", "query"),
    Param.new("Admin-Token", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
