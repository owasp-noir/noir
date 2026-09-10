require "../../func_spec.cr"

# Express routes registered through a project-local forwarding helper.
# The layout mirrors NodeBB, where the whole write API, every page route
# and every admin page route is registered this way:
#
#   routes/helpers.js       helpers.setupApiRoute = function (...args) {
#                             const [router, verb, name] = args;
#                             router[verb](name, middlewares, controller);
#                           }
#                           helpers.setupPageRoute = function (...args) {
#                             const [router, name] = args;
#                             router.get(name, …);
#                             router.get(`/api${name}`, …);
#                           }
#   routes/index.js         const { setupPageRoute } = helpers;
#                           setupPageRoute(router, '/login', [], …)
#   routes/write/index.js   router.use('/api/v3/users', require('./users')())
#   routes/write/users.js   const { setupApiRoute } = routeHelpers;
#                           setupApiRoute(router, 'get', '/:uid', [], …)
#
# Three things have to line up for this to work: reading the verb and the
# path out of the helper's positional destructuring of a rest parameter,
# following `const { setupApiRoute } = routeHelpers` back to the module
# that defines it, and taking the `/api/v3/users` prefix from a mount
# whose router is a function parameter.
#
# The fixture also pins what must NOT be emitted:
#   * the commented-out `setupApiRoute` in routes/write/users.js,
#   * the call whose path is built by a function (`buildPath('exports')`),
#   * the call from test/api.js,
#   * `/api${name}` from the helper's own body — that line is the
#     definition of a rewrite, not a registration.

expected_endpoints = [
  Endpoint.new("/login", "GET"),
  Endpoint.new("/api/login", "GET"),
  Endpoint.new("/reset/:code?", "GET", [Param.new("code", "", "path")]),
  Endpoint.new("/api/reset/:code?", "GET", [Param.new("code", "", "path")]),
  Endpoint.new("/api/v3/ping", "GET"),
  Endpoint.new("/api/v3/users/:uid", "GET", [Param.new("uid", "", "path")]),
  Endpoint.new("/api/v3/users/:uid", "PUT", [Param.new("uid", "", "path")]),
  Endpoint.new("/api/v3/users/:uid/tokens/:token", "DELETE",
    [Param.new("uid", "", "path"), Param.new("token", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/express_route_helper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
