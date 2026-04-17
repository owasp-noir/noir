require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/pets", "GET"),
  Endpoint.new("/v1/pets", "POST"),
  Endpoint.new("/v1/pets/search", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/v1/pets/upload", "POST", [
    Param.new("file", "", "form"),
    Param.new("description", "", "form"),
  ]),
  Endpoint.new("/v1/pets/submit", "POST", [
    Param.new("pet_name", "", "form"),
  ]),
  Endpoint.new("/v1/pets/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/v1/pets/{petId}", "PUT", [Param.new("petId", "", "path")]),
]

FunctionalTester.new("fixtures/specification/oas2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
