require "../../func_spec.cr"

# Test cases for Express prefix handling edge cases
#
# Issue 1: Prefix "bleeds" to unmounted routers when a mounted symbol is a factory function
#   - When mounting createPublicRouter() from a file that also exports createAdminRouter(),
#     the /api prefix should NOT apply to createAdminRouter() routes.
#
# Issue 2: Mounted router detection assumes the router is the last identifier in use(...) args
#   - In app.use('/users', userRoutes, auth), the router is userRoutes (first), not auth (last).
#
# Issue 3: Same-file nested routers with middleware
#   - In router.use('/sub', subRouter, logger), subRouter should get the prefix, not logger.

# Expected CORRECT behavior:
expected_endpoints = [
  # From createPublicRouter() mounted at /api
  Endpoint.new("/api/public", "GET"),

  # From createAdminRouter() - NOT MOUNTED, should have NO prefix
  # If this appears as /api/admin, that's the BUG (prefix bleed)
  Endpoint.new("/admin", "GET"),

  # From userRoutes mounted at /users (first identifier, not 'auth')
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/users/create", "POST"),

  # From subRouter mounted at /nested/sub (first identifier, not 'logger')
  Endpoint.new("/nested/sub/items", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_prefix_issues/", {
  :techs => 1,
}, expected_endpoints).perform_tests
