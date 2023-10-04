require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/pets", "GET"),
  Endpoint.new("/pets", "POST"),
  Endpoint.new("/pets/{petId}", "GET"),
  Endpoint.new("/pets/{petId}", "PUT"),
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
