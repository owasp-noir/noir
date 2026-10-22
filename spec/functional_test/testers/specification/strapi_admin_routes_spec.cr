require "../../func_spec.cr"

# Only the src/api/<name>/routes routers are content-API routes. The plugin
# router typed `admin` (src/plugins/todo/server/routes/admin.js) is served by
# the admin API, so it must not surface as `/api` (nor `GET /api` for path `/`).
expected_endpoints = [
  Endpoint.new("/api/articles/featured", "GET"),
  # A stray `type: 'admin'` under src/api/<name>/routes is overridden by
  # Strapi to `content-api`, so it still serves under /api.
  Endpoint.new("/api/stray/ping", "GET"),
]

FunctionalTester.new("fixtures/specification/strapi_admin_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
