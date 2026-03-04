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
  # api_router.go: PATCH method with path and form params
  Endpoint.new("/items/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("name", "", "form"),
  ]),
  # api_router.go: multiple path params with query param
  Endpoint.new("/shops/:shopId/items/:itemId", "GET", [
    Param.new("shopId", "", "path"),
    Param.new("itemId", "", "path"),
    Param.new("detail", "", "query"),
  ]),
  # api_router.go: POST with form, header and cookie
  Endpoint.new("/upload", "POST", [
    Param.new("file_name", "", "form"),
    Param.new("Content-Type", "", "header"),
    Param.new("auth_token", "", "cookie"),
  ]),
  # api_router.go: DELETE with path param and header
  Endpoint.new("/cache/:key", "DELETE", [
    Param.new("key", "", "path"),
    Param.new("X-Admin-Key", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/go/fasthttp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
