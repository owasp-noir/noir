require "../../func_spec.cr"

# A class literally named `Test` / `Tests` is not a JUnit class: the tutorial
# servlet `Test.java` and `Tests.kt` still serve their routes. The same
# `*Test` suffix rule covers Kotlin, so `FormBindingTest.kt` (a test-kit
# controller published from `src/main/kotlin`) stays suppressed.
expected_endpoints = [
  Endpoint.new("/test", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/tests-kt/real", "GET"),
]

FunctionalTester.new("fixtures/java/test_class_names/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
