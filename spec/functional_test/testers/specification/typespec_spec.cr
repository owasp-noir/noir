require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/pets", "GET", [
    Param.new("filter", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/v1/pets", "POST", [
    Param.new("pet", "", "json"),
  ]),
  Endpoint.new("/v1/pets/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/v1/pets/{id}/avatar", "POST", [
    Param.new("id", "", "path"),
    Param.new("file", "", "json"),
  ]),
  Endpoint.new("/v1/health", "GET", [] of Param),
]

FunctionalTester.new("fixtures/specification/typespec/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
