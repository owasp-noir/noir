require "../../func_spec.cr"

# Regression test for #2556: a project-defined `@HttpMethod("QUERY")`
# annotation (declared in its own file, JAX-RS's general custom-verb
# mechanism) must resolve to verb QUERY on Dropwizard too — it shares
# `TreeSitterJaxRsExtractor` with `java_jaxrs` / `java_quarkus` — while
# built-in `@GET` handling stays unaffected.
expected_endpoints = [
  Endpoint.new("/search", "QUERY", [
    Param.new("query", "", "json"),
    Param.new("limit", "", "json"),
  ]),
  Endpoint.new("/search/status", "GET"),
]

FunctionalTester.new("fixtures/java/dropwizard_custom_verb/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
