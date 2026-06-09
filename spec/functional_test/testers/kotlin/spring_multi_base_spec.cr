require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/from-a", "GET"),
  Endpoint.new("/from-b", "GET"),
]

FunctionalTester.new("fixtures/kotlin/spring_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
