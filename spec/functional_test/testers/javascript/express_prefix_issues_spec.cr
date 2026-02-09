require "../../func_spec.cr"

# Test cases for Express prefix handling edge cases
#
# Issue 1: Prefix "bleeds" to unmounted routers when a mounted symbol is a factory function
#   - When mounting createPublicRouter() from a file that also exports createAdminRouter(),
#     the /api prefix should NOT apply to createAdminRouter() routes.
#
# Issue 2: Router detection with multiple identifiers in .use() args
#   - Must handle both patterns:
#     - app.use('/path', router, middleware) - router first
#     - app.use('/path', middleware, router) - middleware first
#
# Issue 3: Same-file nested routers with middleware (both orderings)

# Expected CORRECT behavior:
expected_endpoints = [
  # From createPublicRouter() mounted at /api
  Endpoint.new("/api/public", "GET"),

  # From createAdminRouter() - NOT MOUNTED, should have NO prefix
  # If this appears as /api/admin, that's the BUG (prefix bleed)
  Endpoint.new("/admin", "GET"),

  # From userRoutes mounted at /users (router FIRST, middleware after)
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/users/create", "POST"),

  # From orderRoutes mounted at /orders (middleware FIRST, router after)
  Endpoint.new("/orders/pending", "GET"),
  Endpoint.new("/orders/create", "POST"),

  # From subRouter mounted at /nested/sub (router first, middleware after)
  Endpoint.new("/nested/sub/items", "GET"),

  # From sub2Router mounted at /nested2/sub2 (middleware first, router after)
  Endpoint.new("/nested2/sub2/data", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_prefix_issues/", {
  :techs => 1,
}, expected_endpoints).perform_tests
