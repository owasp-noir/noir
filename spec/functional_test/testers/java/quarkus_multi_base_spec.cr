require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/java/quarkus_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/java/quarkus_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/qa/items", "GET"),
  Endpoint.new("/qb/items", "GET"),
]

FunctionalTester.new("fixtures/java/quarkus_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
