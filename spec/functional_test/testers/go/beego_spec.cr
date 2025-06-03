require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/alice", "POST", [
    Param.new("query", "", "query"),
    Param.new("auth", "", "cookie"),
  ]),
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/go/beego/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
