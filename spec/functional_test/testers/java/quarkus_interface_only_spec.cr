require "../../func_spec.cr"

# openapi-generator `interfaceOnly`: every JAX-RS annotation sits on the
# `@Path` interface, and its implementation imports nothing from `ws.rs`.
expected_endpoints = [
  Endpoint.new("/pets", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/pets", "POST", [Param.new("name", "", "json"), Param.new("tag", "", "json")]),
  Endpoint.new("/pets/{petId}", "GET", [Param.new("petId", "", "path")]),
]

FunctionalTester.new("fixtures/java/quarkus_interface_only/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
