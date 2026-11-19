require "../../func_spec.cr"

# `"\${prop:default}"` mappings resolve against application.yml, falling back
# to the default; an unknown property without one is an empty segment.
expected_endpoints = [
  Endpoint.new("/v2/pet/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/v9/orders/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/v9/orders/raw", "GET"),
]

FunctionalTester.new("fixtures/kotlin/spring_property_placeholder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
