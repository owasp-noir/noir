require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("query", "", "query"),
    Param.new("cookie1", "", "cookie"),
    Param.new("cookie2", "", "cookie"),
  ]),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/query", "POST", [Param.new("query", "", "form")]),
]

FunctionalTester.new("fixtures/ruby_sinatra/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
