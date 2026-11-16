require "../../func_spec.cr"

expected_endpoints = [Endpoint.new("/real", "GET")]

FunctionalTester.new("fixtures/java/spark_static_examples/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
