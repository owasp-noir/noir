require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/accounts/list", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/accounts/create", "POST", [
    Param.new("account_id", "", "json"),
    Param.new("name", "", "json"),
    Param.new("X-Request-Id", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/javascript/koa_prefix_edge_patterns/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
