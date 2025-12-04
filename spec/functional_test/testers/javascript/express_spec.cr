require "../../func_spec.cr"

expected_endpoints = [
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
    Param.new("x-api-key", "", "header"),
  ]),
  # Route with path parameter
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  # Added endpoints
  Endpoint.new("/products", "GET"),
  Endpoint.new("/products", "POST", [
    Param.new("title", "", "json"),
    Param.new("price", "", "json"),
    Param.new("Authorization", "", "header"),
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
  ]),
  # Dynamic path endpoints (from dynamic_paths.js)
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/login", "POST"),
  # router.all expanded to all HTTP methods
  Endpoint.new("/api/catchall", "GET"),
  Endpoint.new("/api/catchall", "POST"),
  Endpoint.new("/api/catchall", "PUT"),
  Endpoint.new("/api/catchall", "DELETE"),
  Endpoint.new("/api/catchall", "PATCH"),
  Endpoint.new("/api/catchall", "HEAD"),
  Endpoint.new("/api/catchall", "OPTIONS"),
  Endpoint.new("/api/v2/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/v2/items/:itemId", "DELETE", [
    Param.new("itemId", "", "path"),
  ]),
  # More router.all endpoints
  Endpoint.new("/api/admin", "GET"),
  Endpoint.new("/api/admin", "POST"),
  Endpoint.new("/api/admin", "PUT"),
  Endpoint.new("/api/admin", "DELETE"),
  Endpoint.new("/api/admin", "PATCH"),
  Endpoint.new("/api/admin", "HEAD"),
  Endpoint.new("/api/admin", "OPTIONS"),
]

FunctionalTester.new("fixtures/javascript/express/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
