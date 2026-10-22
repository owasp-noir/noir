require "../../func_spec.cr"

# restify-router routers defined in their own files and mounted from the
# server (`usersRouter.applyRoutes(server, '/users')`,
# `require('./routes/api').applyRoutes(server, '/api')`) or nested
# (`router.add('/v1', require('./v1'))`). Only same-file applyRoutes was
# resolved, so these routes were reported at their bare paths.

FunctionalTester.new("fixtures/javascript/restify_router_crossfile/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/users/list", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/v1/ping", "GET"),
]).perform_tests
