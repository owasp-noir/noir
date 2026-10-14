require "../../func_spec.cr"

# A Deno Oak service beside a Koa API. Koa's `api.use('/users',
# users.routes())` is Oak's mount shape too, and both write the same
# per-file prefix key: Oak resolving the Koa mount pushed a bare `/users`
# onto the Koa child, so it surfaced twice (and only when Oak ran first).
FunctionalTester.new("fixtures/javascript/oak_koa_sibling/", {
  :techs     => 2,
  :endpoints => 3,
}, [
  Endpoint.new("/api/v1/users/", "GET"),
  Endpoint.new("/api/v1/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/ping", "GET"),
]).perform_tests
