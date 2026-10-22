require "../../func_spec.cr"

# A route template comes from the verb attribute's own parens (or a `Route` on
# the same line), never from a sibling attribute's string literal; `ActionName`
# renames the conventional action; a constant route argument is skipped.
expected_endpoints = [
  # LogController — conventional routes (`{controller}/{action}`).
  Endpoint.new("/Log/List", "GET"),
  Endpoint.new("/Log/List", "POST", [Param.new("q", "", "form")]),
  Endpoint.new("/Log/Edit", "POST"),
  Endpoint.new("/Log/Secure", "GET"),
  Endpoint.new("/Log/Feed", "GET"),
  Endpoint.new("/Log/Stacked", "GET"),
  # ItemsController — `[Route("api/items")]`.
  Endpoint.new("/api/items/rm", "DELETE"),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/api/items", "PUT"),
  Endpoint.new("/api/items/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_attribute_templates/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
