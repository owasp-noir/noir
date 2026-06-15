require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/pets", "GET"),
  Endpoint.new("/v1/pets", "POST", [
    Param.new("name", "", "json"),
  ]),
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
  Endpoint.new("/v1/pets/{petId}", "PUT", [
    Param.new("petId", "", "path"),
    Param.new("name", "", "json"),
    Param.new("breed", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/oas2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

FunctionalTester.new("fixtures/specification/oas2_security/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/v1/items", "GET", [
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/v1/items", "POST", [
    Param.new("name", "", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/v1/public", "GET"),
  Endpoint.new("/v1/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("api_key", "", "query"),
  ]),
]).perform_tests

FunctionalTester.new("fixtures/specification/oas2_edge_cases/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/orders", "GET", [
    Param.new("X-Tenant", "", "header"),
    Param.new("state", "", "query"),
  ]),
  Endpoint.new("/api/orders", "POST", [
    Param.new("X-Tenant", "", "header"),
    Param.new("name", "", "json"),
    Param.new("expedited", "", "json"),
    Param.new("gift_message", "", "json"),
  ]),
  Endpoint.new("/api/uploads", "POST", [
    Param.new("file", "", "form"),
    Param.new("description", "", "form"),
  ]),
]).perform_tests
