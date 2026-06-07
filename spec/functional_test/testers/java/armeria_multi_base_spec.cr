require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/java/armeria_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/java/armeria_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/a-only", "GET"),
  Endpoint.new("/b/b-only", "GET"),
]

FunctionalTester.new("fixtures/java/armeria_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("java_armeria"),
}).perform_tests
