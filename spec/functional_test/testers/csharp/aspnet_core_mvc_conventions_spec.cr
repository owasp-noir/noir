require "../../func_spec.cr"

# #3302: an `IApplicationModelConvention` that combines a constant
# `RouteAttribute` with every controller selector prefixes the attribute
# routes; `[FromBody] Create.Command` reads the nested `Command` of the
# `Create` its namespace reaches, not another `Command`; `MapHealthChecks`
# and `MapForwarder` map their pattern for every method.
expected_endpoints = [
  Endpoint.new("/api/tags", "GET"),
  Endpoint.new("/api/articles", "POST", [Param.new("article", "", "json")]),
  Endpoint.new("/health", "ANY"),
  Endpoint.new("/product-images/{id}", "ANY", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_conventions/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
