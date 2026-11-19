require "../../func_spec.cr"

# Carter base paths from a constant (`: base(BasePath)`) and a C# 12
# primary-constructor base (`: CarterModule("/k04")`), and route and group
# templates held in constants.
expected_endpoints = [
  Endpoint.new("/c10/orders/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/k04/primary-ctor", "GET"),
  Endpoint.new("/catalog/items/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/csharp/carter_base_path/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
