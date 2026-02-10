require "../../func_spec.cr"

# Test 3-level cross-file router nesting.
#
# Structure:
#   app.js          -> app.use('/api', level1Router)        (level 1)
#   routes/level1.js -> router.use('/v1', level2Router)     (level 2)
#   routes/level2.js -> router.use('/admin', level3Router)  (level 3)
#   routes/level3.js -> router.get('/users'), router.post('/users')
#
# This exercises the fix-point loop in process_deferred_mounts:
# level3's prefix depends on level2's, which depends on level1's.
# A single-pass deferred resolution would fail to resolve level3.

expected_endpoints = [
  # Direct route on app
  Endpoint.new("/health", "GET"),

  # Level 1 route: /api + /info
  Endpoint.new("/api/info", "GET"),

  # Level 2 route: /api + /v1 + /status
  Endpoint.new("/api/v1/status", "GET"),

  # Level 3 routes: /api + /v1 + /admin + /users
  Endpoint.new("/api/v1/admin/users", "GET"),
  Endpoint.new("/api/v1/admin/users", "POST"),
]

FunctionalTester.new("fixtures/javascript/express_deep_nesting/", {
  :techs => 1,
}, expected_endpoints).perform_tests
