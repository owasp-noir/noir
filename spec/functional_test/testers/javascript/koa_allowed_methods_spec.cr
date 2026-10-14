require "../../func_spec.cr"

# `api.use('/users', users.routes(), users.allowedMethods())`: the trailing
# middleware argument must not cost the cross-file child its mount prefix.
expected_endpoints = [
  Endpoint.new("/users/", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/koa_allowed_methods/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
