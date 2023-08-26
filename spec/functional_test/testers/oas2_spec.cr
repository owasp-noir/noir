require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/v1/pets", "GET"),
  Endpoint.new("/v1/pets", "POST", [Param.new("pet", "", "json")]),
  Endpoint.new("/v1/pets/{petId}", "GET"),
  Endpoint.new("/v1/pets/{petId}", "PUT", [Param.new("pet", "", "json")]),
]

FunctionalTester.new("fixtures/oas2/", {
  :techs     => 1,
  :endpoints => 4,
}, extected_endpoints).test_all
