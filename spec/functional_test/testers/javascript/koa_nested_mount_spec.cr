require "../../func_spec.cr"

# koa-router mounts sub-routers through a `.routes()` middleware chain:
#   api.use(usersRouter)              // usersRouter = require('./users-router')
#   router.use('/api', api.routes())  // api aggregated under /api
# Every sub-router's route must inherit the `/api` prefix even though the
# sub-routers live in separate files and `api`/`router` are local
# aggregators with no backing file.
expected_endpoints = [
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/login", "POST"),
  Endpoint.new("/api/user", "GET"),
  Endpoint.new("/api/articles", "GET"),
  Endpoint.new("/api/articles/:slug", "GET"),
]

FunctionalTester.new("fixtures/javascript/koa_nested_mount/", {
  :techs     => 1,
  :endpoints => 5,
}, expected_endpoints).perform_tests
