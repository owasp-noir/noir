require "../../func_spec.cr"

# Request data bound to a local first: `const body = req.body; body.x`.
expected_endpoints = [
  Endpoint.new("/x00-control", "POST", [Param.new("title", "", "json"), Param.new("page", "", "query")]),
  Endpoint.new("/x01-alias", "POST", [
    Param.new("title", "", "json"), Param.new("slug", "", "json"), Param.new("page", "", "query"),
  ]),
  Endpoint.new("/x02-alias-destructure", "POST", [Param.new("email", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/x04-or-default", "POST", [
    Param.new("limit", "", "query"), Param.new("offset", "", "query"), Param.new("token", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express_request_alias/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
