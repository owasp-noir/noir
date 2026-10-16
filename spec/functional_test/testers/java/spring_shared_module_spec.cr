require "../../func_spec.cr"

# #3087: DTOs in a shared module that is not a direct sibling of the
# controller's module; #3089: a constant inherited from an implemented interface.
expected_endpoints = [
  Endpoint.new("/api/orders", "POST", [
    Param.new("sku", "", "json"),
    Param.new("qty", "", "json"),
  ]),
  Endpoint.new("/api/orders/search", "GET", [
    Param.new("sku", "", "query"),
    Param.new("qty", "", "query"),
  ]),
  Endpoint.new("/api/notes", "POST", [Param.new("memo", "", "json")]),
  Endpoint.new("/api/hop", "GET", [Param.new("X-Relay-Origin", "", "header")]),
]

FunctionalTester.new("fixtures/java/spring_shared_module/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
