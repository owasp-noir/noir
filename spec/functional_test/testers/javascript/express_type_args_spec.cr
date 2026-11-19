require "../../func_spec.cr"

# `router.get<Params, Res, Body, Query>(…)` (@types/express generics).
expected_endpoints = [
  Endpoint.new("/api/x00-control/:id", "GET", [Param.new("id", "", "path"), Param.new("verbose", "", "query")]),
  Endpoint.new("/api/x01-generic/:id", "GET", [Param.new("id", "", "path"), Param.new("verbose", "", "query")]),
  Endpoint.new("/api/x02-generic/:id", "POST", [
    Param.new("id", "", "path"), Param.new("name", "", "json"), Param.new("x-tenant", "", "header"),
  ]),
  Endpoint.new("/x03-inline/:id", "GET", [Param.new("id", "", "path"), Param.new("sid", "", "cookie")]),
]

FunctionalTester.new("fixtures/javascript/express_type_args/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
