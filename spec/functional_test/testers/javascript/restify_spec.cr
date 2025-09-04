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
  Endpoint.new("/products", "GET", [
    Param.new("limit", "", "query"),
  ]),
  # New added endpoints - server defined
  Endpoint.new("/items", "GET", [
    Param.new("category", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/items", "POST", [
    Param.new("name", "", "json"),
    Param.new("description", "", "json"),
    Param.new("X-CSRF-Token", "", "header"),
  ]),
  Endpoint.new("/item/:itemId", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("fields", "", "query"),
  ]),
  Endpoint.new("/info", "GET"),
  # New added endpoints - router defined with path prefix
  Endpoint.new("/dashboard", "GET", [
    Param.new("view", "", "query"),
    Param.new("Admin-Key", "", "header"),
  ]),
  Endpoint.new("/users/create", "POST", [
    Param.new("username", "", "json"),
    Param.new("role", "", "json"),
    Param.new("adminToken", "", "cookie"),
  ]),
  # New added endpoints - api router endpoints
  Endpoint.new("/products/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("price", "", "json"),
    Param.new("stock", "", "json"),
    Param.new("X-Access-Key", "", "header"),
  ]),
  Endpoint.new("/products/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("X-Confirm", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/javascript/restify/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
