require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("query", "", "query"),
    Param.new("cookie1", "", "cookie"),
    Param.new("cookie2", "", "cookie"),
  ]),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/api/widgets", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/widgets", "POST", [
    Param.new("HTTP_X_TRACE_ID", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/ruby/sinatra/", {
  :techs     => 1,
  :endpoints => 4,
}, expected_endpoints).perform_tests
