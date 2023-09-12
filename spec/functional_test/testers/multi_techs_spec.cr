require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/query", "POST", [Param.new("query", "", "form")]),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/pets", "GET"),
  Endpoint.new("/pets", "POST"),
  Endpoint.new("/pets/{petId}", "GET"),
  Endpoint.new("/pets/{petId}", "PUT"),
]

FunctionalTester.new("fixtures/multi_techs/", {
  :techs     => 3,
  :endpoints => 8,
}, extected_endpoints).test_all
