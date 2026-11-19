require "../../func_spec.cr"

# `new Router({ prefix: '/api' })` then `router.get(...).post(...).del(...)`:
# every link of the chain is served under the prefix, not just the first.
FunctionalTester.new("fixtures/javascript/koa_chain_prefix/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/:id", "DELETE", [Param.new("id", "", "path")]),
]).perform_tests
