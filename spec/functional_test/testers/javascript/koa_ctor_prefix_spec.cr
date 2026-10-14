require "../../func_spec.cr"

# `const api = new Router({ prefix: '/api' })` then
# `api.use('/users', users.routes())`: the cross-file child is served under
# the parent's constructor prefix too.
expected_endpoints = [
  Endpoint.new("/api/users/", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/koa_ctor_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
