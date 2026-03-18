require "../../func_spec.cr"

expected_endpoints = [
  # Basic GET route
  Endpoint.new("/", "GET", [
    Param.new("name", "", "query"),
    Param.new("x-api-key", "", "header"),
  ]),
  # POST route with JSON body
  Endpoint.new("/register", "POST", [
    Param.new("username", "", "json"),
    Param.new("client-id", "", "header"),
  ]),
  # Route with path parameter
  Endpoint.new("/users/:userId", "GET", [
    Param.new("userId", "", "path"),
    Param.new("fields", "", "query"),
  ]),
  # GET products
  Endpoint.new("/products", "GET", [
    Param.new("category", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  # POST products
  Endpoint.new("/products", "POST", [
    Param.new("name", "", "json"),
    Param.new("store-id", "", "header"),
  ]),
  # Dashboard with cookie
  Endpoint.new("/dashboard", "GET", [
    Param.new("view", "", "query"),
    Param.new("sessionId", "", "cookie"),
  ]),
  # PUT settings
  Endpoint.new("/settings", "PUT", [
    Param.new("theme", "", "json"),
    Param.new("authorization", "", "header"),
  ]),
  # DELETE with path param
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("x-admin-key", "", "header"),
  ]),
  # PATCH with path param and body
  Endpoint.new("/users/:id/profile", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("bio", "", "json"),
  ]),
  # Form body with parseBody
  Endpoint.new("/upload", "POST", [
    Param.new("file", "", "form"),
    Param.new("x-upload-token", "", "header"),
  ]),
  # app.on() with specific method
  Endpoint.new("/health", "GET", [
    Param.new("format", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/javascript/hono/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
