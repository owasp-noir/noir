require "../../func_spec.cr"

# go-zero registers routes three ways, all exercised by the fixture:
#   - `server.AddRoute(rest.Route{...})` single struct (main.go)
#   - `apiGroup := server.Group("/api/v1")` + `apiGroup.AddRoute(...)`
#     group prefix -> `/api/v1/products`
#   - `server.Get/Post/Put(...)` verb form
#   - `.api` DSL with `@server(prefix: /admin)` -> `/admin/...`
# The struct-form routes (`AddRoute`), the `/api/v1` group prefix, the
# `/admin` `.api` prefix, and the `/` home route were all previously
# missed (FN); they're now resolved to full mounted paths and dedupe
# against their `.api` counterparts by (method, url).
expected_endpoints = [
  # Root + main-service routes (main.go AddRoute / .api, no prefix).
  Endpoint.new("/", "GET"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/profile", "PUT"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/login", "POST"),
  # Group-prefixed routes (`server.Group("/api/v1")`).
  Endpoint.new("/api/v1/products", "GET"),
  Endpoint.new("/api/v1/products", "POST"),
  # `@server(prefix: /admin)` `.api` block.
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/admin/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/users", "POST"),
]

FunctionalTester.new("fixtures/go/gozero/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
