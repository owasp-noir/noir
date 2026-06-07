require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/python/robyn_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/python/robyn_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/service-a/items", "GET"),
  Endpoint.new("/local", "GET"),
]

FunctionalTester.new("fixtures/python/robyn_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("python_robyn"),
}).perform_tests
