require "../../func_spec.cr"

# Oak routers mount sub-routers through a `.routes()`/`.allowedMethods()`
# middleware chain, same shape as koa-router:
#   api.use(usersRouter.routes())        // usersRouter imported from another file
#   router.use('/api', api.routes(), api.allowedMethods())
# Every sub-router's route must inherit the `/api` prefix even though the
# sub-routers live in separate files and `api`/`router` are local
# aggregators with no backing file.
expected_endpoints = [
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/login", "POST"),
  Endpoint.new("/api/user", "GET"),
  Endpoint.new("/api/articles", "GET"),
  Endpoint.new("/api/articles/:slug", "GET", [
    Param.new("slug", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/oak_nested_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
