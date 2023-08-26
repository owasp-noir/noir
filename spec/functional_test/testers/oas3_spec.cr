require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/pets", "GET"),
  Endpoint.new("/pets", "POST"),
  Endpoint.new("/pets/{petId}", "GET"),
  Endpoint.new("/pets/{petId}", "PUT"),
]

FunctionalTester.new("fixtures/oas3/", {
  :techs     => 1,
  :endpoints => 4,
}, extected_endpoints).test_all
