require "../../func_spec.cr"

expected_endpoints = [
  # Basic API route
  Endpoint.new("/api/hello", "GET"),
  Endpoint.new("/api/hello", "POST"),
  Endpoint.new("/api/hello", "PUT"),
  Endpoint.new("/api/hello", "DELETE"),
  Endpoint.new("/api/hello", "PATCH"),
  Endpoint.new("/api/hello", "HEAD"),
  Endpoint.new("/api/hello", "OPTIONS"),
  
  # GET-only route with query parameters
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("search", "", "query"),
  ]),
  
  # POST-only route with body parameters
  Endpoint.new("/api/users", "POST", [
    Param.new("username", "", "body"),
    Param.new("email", "", "body"),
    Param.new("password", "", "body"),
  ]),
  
  # Dynamic route with path parameter (from [id].ts)
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/:id", "POST", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/:id", "HEAD", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/:id", "OPTIONS", [
    Param.new("id", "", "path"),
  ]),
  
  # DELETE-only route with path parameter and header (from [id].delete.ts)
  # This will override the DELETE from [id].ts due to deduplication
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
  
  # Server route (without /api prefix) with cookie
  Endpoint.new("/auth", "GET", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/auth", "POST", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/auth", "PUT", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/auth", "DELETE", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/auth", "PATCH", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/auth", "HEAD", [
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/auth", "OPTIONS", [
    Param.new("session", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nuxtjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
