require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/planets", "GET", [Param.new("limit", "", "query"), Param.new("cursor", "", "query")]),
  Endpoint.new("/planets/{id}", "GET", [Param.new("id", "", "path")]),
  # No `method`: POST. `.input()` before `.route()`, `PlanetSchema.omit({ id })`.
  Endpoint.new("/planets", "POST", [Param.new("name", "", "json"), Param.new("description", "", "json")]),
  # Mounted through `os.prefix('/admin/planets').router({...})`.
  Endpoint.new("/admin/planets/{id}", "DELETE", [Param.new("id", "", "path")]),
]

# The RPC-only `ping` procedure has no `.route()` and is not reported.
FunctionalTester.new("fixtures/typescript/orpc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
