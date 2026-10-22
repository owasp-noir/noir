require "../../func_spec.cr"

# Gradle's extra test source sets (`src/jmh`, `src/testFixtures`) and JUnit
# classes named `*Test.java` / `*Tests.java` that sit in `src/main/java` of a
# published test kit (the Micronaut TCK shape) declare controllers that no
# application serves. `src/test/webapp` JSPs and `web.xml` are test-only too.
# `Latest.java` ends in "est.java" but is a real controller.
expected_endpoints = [
  Endpoint.new("/books/list", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/latest/news", "GET"),
  Endpoint.new("/index.jsp", "GET", [Param.new("q", "", "query")]),
]

FunctionalTester.new("fixtures/java/test_source_sets/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
