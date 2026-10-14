require "../../func_spec.cr"

# `const v1 = express.Router()` mounts imported routers
# (`v1.use('/users', usersRouter)`) and is itself mounted with
# `app.use('/api/v1', v1)`: the imported routers sit under both prefixes.
FunctionalTester.new("fixtures/javascript/express_local_router_mount/", {
  :techs     => 1,
  :endpoints => 8,
}, [
  Endpoint.new("/api/v1/users/", "GET", [Param.new("page", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/api/v1/users/", "POST", [Param.new("name", "", "json"), Param.new("email", "", "json")]),
  Endpoint.new("/api/v1/users/:userId", "GET", [Param.new("userId", "", "path")]),
  Endpoint.new("/api/v1/users/:userId", "PUT", [Param.new("userId", "", "path")]),
  Endpoint.new("/api/v1/users/:userId", "DELETE", [Param.new("userId", "", "path")]),
  Endpoint.new("/api/v1/auth/login", "POST", [Param.new("email", "", "json")]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/health", "HEAD"),
]).perform_tests

# The same through an app that is not named `app`:
# `const server = express(); server.use('/api', apiRouter)`.
FunctionalTester.new("fixtures/javascript/express_server_local_router/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/", "GET"),
]).perform_tests
