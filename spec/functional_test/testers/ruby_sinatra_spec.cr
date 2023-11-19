require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/query", "POST", [Param.new("query", "", "form")]),
]

FunctionalTester.new("fixtures/ruby_sinatra/", {
  :techs     => 1,
  :endpoints => 2,
}, extected_endpoints).test_all
