require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/query", "POST", [Param.new("query", "", "form")]),
]

FunctionalTester.new("fixtures/crystal_kemal/", {
  :techs     => 1,
  :endpoints => 3,
}, extected_endpoints).test_all
