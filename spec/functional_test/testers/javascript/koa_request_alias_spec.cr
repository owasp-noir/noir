require "../../func_spec.cr"

# `const body = ctx.request.body; body.x`, `const query = ctx.query`.
expected_endpoints = [
  Endpoint.new("/k00-control", "POST", [Param.new("title", "", "json"), Param.new("page", "", "query")]),
  Endpoint.new("/k01-alias", "POST", [Param.new("title", "", "json"), Param.new("page", "", "query")]),
  Endpoint.new("/k02-alias-destructure", "POST", [Param.new("email", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/k03-ctx-destructure", "POST", [Param.new("viaRequest", "", "json"), Param.new("viaBody", "", "json")]),
]

FunctionalTester.new("fixtures/javascript/koa_request_alias/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
