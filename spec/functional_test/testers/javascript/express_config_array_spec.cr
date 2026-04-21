require "../../func_spec.cr"

# Regression guard for two-level Express mount resolution through a
# route-config array iterated with forEach. The layout mirrors
# hagopj13/node-express-boilerplate, where it was originally found:
#
#   app.js                   app.use('/v1', routes)
#   routes/v1/index.js       defaultRoutes.forEach((r) =>
#                              router.use(r.path, r.route))
#                            defaultRoutes: [
#                              { path: '/auth',  route: authRoute },
#                              { path: '/users', route: userRoute },
#                            ]
#   routes/v1/auth.route.js  router.post('/register', …)
#   routes/v1/user.route.js  router.route('/').get(...).post(...)
#                            router.route('/:userId').get().patch().delete()
#
# Every leaf endpoint must be resolved with the full `/v1/{auth,users}`
# prefix. Pre-fix, noir only had `/register`, `/login`, `/`, `/:userId`
# because the mount scanner's regex required a string literal and could
# not see through `router.use(r.path, r.route)`. This spec fails if
# that regression comes back.

expected_endpoints = [
  Endpoint.new("/v1/auth/register", "POST"),
  Endpoint.new("/v1/auth/login", "POST"),
  Endpoint.new("/v1/auth/logout", "POST"),
  Endpoint.new("/v1/users/", "GET"),
  Endpoint.new("/v1/users/", "POST"),
  Endpoint.new("/v1/users/:userId", "GET", [Param.new("userId", "", "path")]),
  Endpoint.new("/v1/users/:userId", "PATCH", [Param.new("userId", "", "path")]),
  Endpoint.new("/v1/users/:userId", "DELETE", [Param.new("userId", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/express_config_array/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
