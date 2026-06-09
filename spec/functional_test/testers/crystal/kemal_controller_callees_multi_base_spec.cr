require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/crystal/kemal_controller_callees_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/crystal/kemal_controller_callees_multi_base/service_b"),
]

a_endpoint = Endpoint.new("/a", "GET")
a_endpoint.push_callee(Callee.new("aService.load", line: 3))

b_endpoint = Endpoint.new("/b", "GET")
b_endpoint.push_callee(Callee.new("bService.load", line: 3))

expected_endpoints = [
  a_endpoint,
  b_endpoint,
]

FunctionalTester.new("fixtures/crystal/kemal_controller_callees_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"           => YAML::Any.new(base_paths),
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_kemal"),
}).perform_tests
