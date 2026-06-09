require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/haskell/servant_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/haskell/servant_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/service-a", "GET"),
  Endpoint.new("/service-b", "GET"),
]

FunctionalTester.new("fixtures/haskell/servant_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("haskell_servant"),
}).perform_tests
