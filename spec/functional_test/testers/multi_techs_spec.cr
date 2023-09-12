require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/query", "POST", [Param.new("query", "", "form")]),
  Endpoint.new("/socket", "GET"),
]

FunctionalTester.new("fixtures/multi_techs/", {
  :techs     => 2,
  :endpoints => 4,
}, extected_endpoints).test_all
