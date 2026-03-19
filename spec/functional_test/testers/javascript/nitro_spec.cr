require "../../func_spec.cr"

expected_endpoints = [
  # Basic route
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/hello", "POST"),
  Endpoint.new("/hello", "PUT"),
  Endpoint.new("/hello", "DELETE"),
  Endpoint.new("/hello", "PATCH"),
  Endpoint.new("/hello", "HEAD"),
  Endpoint.new("/hello", "OPTIONS"),

  # GET-only route with query parameters
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("search", "", "query"),
  ]),

  # POST-only route with body parameters
  Endpoint.new("/users", "POST", [
    Param.new("username", "", "body"),
    Param.new("email", "", "body"),
    Param.new("password", "", "body"),
  ]),

  # Dynamic route with path parameter (from [id].ts)
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "PATCH", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "HEAD", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/users/:id", "OPTIONS", [
    Param.new("id", "", "path"),
  ]),

  # DELETE-only route with path parameter and header (from [id].delete.ts)
  Endpoint.new("/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nitro/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
