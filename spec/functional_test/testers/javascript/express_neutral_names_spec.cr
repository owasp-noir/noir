require "../../func_spec.cr"

# Test cases for Express router detection with neutral/generic names
#
# These tests verify that router detection works correctly even when:
# - Variable names don't contain "route" or "router"
# - Folder paths don't contain "/routes/" or "/middleware/"
# - Middleware appears before router in .use() calls
# - inline require() is not at the end of arguments
#
# The fix uses content-based detection: files with route definitions
# (.get, .post, etc.) are identified as routers, not middleware.

expected_endpoints = [
  # Test Case 1: Neutral names - middleware first, router after
  # app.use('/x', check, api) - api is the router (has routes)
  Endpoint.new("/x/a", "GET"),

  # Test Case 2: Inline require() NOT at end of args
  # app.use('/y', require('./handlers/data'), mw)
  Endpoint.new("/y/b", "GET"),

  # Test Case 3: Multiple neutral identifiers
  # app.use('/z', filter, processor, handler) - processor has routes
  Endpoint.new("/z/c", "GET"),
  # handler also has routes but wasn't the mounted router for /z prefix
  Endpoint.new("/d", "GET"),

  # Test Case 4: Same-file with neutral names
  # parent.use('/child', guard, child) - child is the router
  Endpoint.new("/parent/child/endpoint", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_neutral_names/", {
  :techs => 1,
}, expected_endpoints).perform_tests
