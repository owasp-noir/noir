require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  # Cross-file koa-router `.routes()` mounts carry their app.js prefix:
  #   app.use('/app_prefix', appRouter.routes())  -> /app_prefix/info
  #   app.use('/api/v1', apiV1Routes.routes())    -> /api/v1/status
  Endpoint.new("/app_prefix/info", "GET"),
  Endpoint.new("/admin/settings", "GET"),
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/simple", "GET"),
  Endpoint.new("/items/:itemId", "DELETE", [
    Param.new("itemId", "", "path"),
  ]),
  Endpoint.new("/named/status", "GET"),
  Endpoint.new("/everything", "GET"),
  Endpoint.new("/everything", "POST"),
  Endpoint.new("/everything", "PUT"),
  Endpoint.new("/everything", "DELETE"),
  Endpoint.new("/everything", "PATCH"),
  Endpoint.new("/everything", "HEAD"),
  Endpoint.new("/everything", "OPTIONS"),
  # Strapi-style declarative `{method, path, handler}` route
  # entries. Plugins under `@strapi/plugin-*` export these from
  # `server/routes/**/*.js` and the standard verb DSL never fires.
  Endpoint.new("/strapi/items", "GET"),
  Endpoint.new("/strapi/items", "POST"),
  Endpoint.new("/strapi/items/:id", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/strapi/items/:id", "DELETE", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/koa/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
