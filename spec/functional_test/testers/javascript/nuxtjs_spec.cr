require "../../func_spec.cr"

expected_endpoints = [
  # `defineEventHandler` accepts any HTTP method, so files
  # without a method-suffixed name emit a single `ANY` endpoint
  # rather than a near-duplicate row for every verb.
  Endpoint.new("/api/hello", "ANY"),

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

  # Dynamic route with path parameter (from [id].ts).
  Endpoint.new("/api/users/:id", "ANY", [
    Param.new("id", "", "path"),
  ]),

  # DELETE-only route with path parameter and header (from [id].delete.ts).
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),

  # Catch-all dynamic route with getRouterParam and destructured query.
  Endpoint.new("/api/blog/:slug", "GET", [
    Param.new("slug", "", "path"),
    Param.new("tag", "", "query"),
  ]),

  # Validated body/header helpers common in Nuxt/Nitro apps.
  Endpoint.new("/api/profile", "POST", [
    Param.new("username", "", "body"),
    Param.new("email", "", "body"),
    Param.new("authorization", "", "header"),
    Param.new("user-agent", "", "header"),
  ]),

  # Server route (without /api prefix) with cookie
  Endpoint.new("/auth", "ANY", [
    Param.new("session", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nuxtjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
