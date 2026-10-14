require "../../func_spec.cr"

# Controller-level `[Route]` lookup: past a long attribute list, one route
# per `[Route]`, inherited from a base controller, and `[area]` replaced.
expected_endpoints = [
  Endpoint.new("/api/reports/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/products/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/v2/products/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/legacy/products", "GET"),
  Endpoint.new("/api/Orders/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/Admin/Dashboard/Index", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_class_routes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
