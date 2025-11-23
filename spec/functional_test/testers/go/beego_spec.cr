require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/alice", "POST", [
    Param.new("query", "", "query"),
    Param.new("auth", "", "cookie"),
  ]),
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/go/beego/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
