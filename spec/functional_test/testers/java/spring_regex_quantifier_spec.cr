require "../../func_spec.cr"

# `{id:[0-9]{3}}`: the flat `\{name:[^{}]+\}` strip could not match a
# constraint containing braces, so the regex reached the report verbatim.
expected_endpoints = [
  Endpoint.new("/api/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/zip/{code}/x", "GET", [Param.new("code", "", "path")]),
]

FunctionalTester.new("fixtures/java/spring_regex_quantifier/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
