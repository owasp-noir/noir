require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/upload", "POST", [
    Param.new("name", "", "json"),
    Param.new("auth", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/javascript/express/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
