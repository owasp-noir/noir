require "../../func_spec.cr"

# A class with no `@Path` of its own is the root resource of the `@Path`
# interface it implements (`class PetsApiImpl implements PetsApi`): its
# inherited routes and its own annotated methods sit at the interface path.
expected_endpoints = [
  Endpoint.new("/members", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/members/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/members/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/v2/teams/{name}", "GET", [Param.new("name", "", "path")]),
]

FunctionalTester.new("fixtures/java/jaxrs_interface_root/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
