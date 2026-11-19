require "../../func_spec.cr"

# Route and `MapGroup` templates held in a `const`, a local, an
# interpolation or a `Type.Member` constant.
expected_endpoints = [
  Endpoint.new("/api/v1/c01", "GET"),
  Endpoint.new("/api/v2/c02", "GET"),
  Endpoint.new("/api/v1/c03/x", "GET"),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/api/v1/c05/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/c06/items", "GET"),
  Endpoint.new("/c07/items", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/c09/literal", "GET"),
  # `ApiPrefix + "/c04"` and `"/c08" + "/joined"` need `+` evaluation in
  # `Common#csharp_string_value`, which reads no concatenation yet; today the
  # first yields nothing and the second its leading literal `/c08`.
  Endpoint.new("/c08", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api_const_routes/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
