require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/pets", "GET", [
    Param.new("query","","query"),
    Param.new("sort","","query"),
  ]),
  Endpoint.new("/pets", "POST", [
    Param.new("name","","json"),
  ]),
  Endpoint.new("/pets/{petId}", "GET"),
  Endpoint.new("/pets/{petId}", "PUT", [
    Param.new("breed","","json"),
    Param.new("name","","json"),
  ]),
]

FunctionalTester.new("fixtures/oas3/common/", {
  :techs     => 1,
  :endpoints => 4,
}, extected_endpoints).test_all

FunctionalTester.new("fixtures/oas3/no_servers/", {
  :techs     => 1,
  :endpoints => 1,
}, nil).test_all

FunctionalTester.new("fixtures/oas3/multiple_docs/", {
  :techs     => 1,
  :endpoints => 2,
}, nil).test_all

FunctionalTester.new("fixtures/oas3/nil_cast/", {
  :techs     => 1,
  :endpoints => 0,
}, nil).test_all
