require "../../func_spec.cr"

# `register(AutoLoad, { dir, options: { prefix: '/api' } })` serves every
# loaded plugin under `/api` before its directory prefix. The routes file
# the `users` plugin registers without a prefix stays at `/api/users`.
expected_endpoints = [
  Endpoint.new("/api/", "GET"),
  Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/javascript/fastify_autoload_options_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
