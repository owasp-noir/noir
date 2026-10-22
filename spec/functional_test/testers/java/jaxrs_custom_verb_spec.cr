require "../../func_spec.cr"

# Regression test for #2556: a project-defined `@HttpMethod("QUERY")`
# annotation (declared in its own file, JAX-RS's general custom-verb
# mechanism) must resolve to verb QUERY when applied to a resource
# method in another file, while built-in `@GET` handling stays
# unaffected.
expected_endpoints = [
  Endpoint.new("/search", "QUERY", [
    Param.new("query", "", "json"),
    Param.new("limit", "", "json"),
  ]),
  Endpoint.new("/search/status", "GET"),
]

FunctionalTester.new("fixtures/java/jaxrs_custom_verb/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
