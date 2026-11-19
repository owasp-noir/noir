require "../../func_spec.cr"

# Route and `MapGroup` templates held in a `const`, a local, an
# interpolation, a `Type.Member` constant or a `+` concatenation of those.
expected_endpoints = [
  Endpoint.new("/api/v1/c01", "GET"),
  Endpoint.new("/api/v2/c02", "GET"),
  Endpoint.new("/api/v1/c03/x", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/api/v1/c05/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/c06/items", "GET"),
  Endpoint.new("/c07/items", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/c09/literal", "GET"),
  Endpoint.new("/api/v1/c04", "GET"),
  Endpoint.new("/c08/joined", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api_const_routes/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
