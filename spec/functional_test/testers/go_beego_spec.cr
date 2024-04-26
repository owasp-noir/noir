require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/alice", "POST", [
    Param.new("query", "", "query"),
    Param.new("auth", "", "cookie"),
  ]),
  Endpoint.new("/", "GET"),
]

FunctionalTester.new("fixtures/go_beego/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
