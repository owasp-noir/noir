require "../../func_spec.cr"

# `app.get<{ Querystring: Q }>(…)`: a type-argument list between the verb
# and `(` must not hide the handler's reads.
expected_endpoints = [
  Endpoint.new("/g00-control", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/g01-generic", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/g02-inline-generic", "GET", [Param.new("a", "", "query")]),
  Endpoint.new("/g03-body", "POST", [Param.new("title", "", "json"), Param.new("done", "", "json")]),
  Endpoint.new("/g04-multiline-generic", "GET", [Param.new("x-trace", "", "header")]),
]

FunctionalTester.new("fixtures/javascript/fastify_type_args/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
