require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/v1/pets", "GET"),
  Endpoint.new("/v1/pets", "POST", [Param.new("pet", "", "json")]),
  Endpoint.new("/v1/pets/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/v1/pets/{petId}", "PUT", [Param.new("petId", "", "path"), Param.new("pet", "", "json")]),
]

FunctionalTester.new("fixtures/specification/oas2/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).test_all
