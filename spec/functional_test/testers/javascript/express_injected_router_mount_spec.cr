require "../../func_spec.cr"

# Regression guard for Express mounts whose parent router arrives as a
# function parameter. NodeBB is the shape this came from:
#
#   src/routes/index.js        await writeRoutes.reload({ router: router })
#   src/routes/write/index.js  Write.reload = async (params) => {
#                                const { router } = params;
#                                router.use('/api/v3/users', require('./users')())
#                              }
#   src/routes/write/users.js  router.get('/:uid', …)
#
# `router` is destructured from a parameter, so the mount scanner has
# nothing in the file to resolve its own prefix against. It used to defer
# the mount forever and then drop it, and `users.js` emitted `/:uid`
# instead of `/api/v3/users/:uid`.
#
# `groups` pins the other half of the rule: it is *also* reachable through
# a mount the scanner can resolve (`app.use('/legacy', groupsRoutes())`),
# so the unplaced `/api/v3/groups` mount is discarded rather than adding a
# second copy of the router at a second prefix.

expected_endpoints = [
  Endpoint.new("/api/v3/users/:uid", "GET", [Param.new("uid", "", "path")]),
  Endpoint.new("/api/v3/users/:uid", "DELETE", [Param.new("uid", "", "path")]),
  Endpoint.new("/legacy/:gid", "GET", [Param.new("gid", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/express_injected_router_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
