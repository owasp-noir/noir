require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("query", "", "query"),
  ]),
  Endpoint.new("/pets", "GET", [
    Param.new("query", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/query", "POST", [Param.new("query", "", "form")]),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/pets", "GET"),
  Endpoint.new("/pets", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/pets/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/pets/{petId}", "PUT", [
    Param.new("petId", "", "path"),
    Param.new("breed", "", "json"),
    Param.new("name", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/multi_techs/", {
  :techs     => 3,
  :endpoints => 8,
}, extected_endpoints).test_all
