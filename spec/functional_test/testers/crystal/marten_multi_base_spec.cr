require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/crystal/marten_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/crystal/marten_multi_base/service_b"),
]

service_a = Endpoint.new("/a/users", "GET").tap do |ep|
  ep.push_callee(Callee.new("ServiceA.list", line: 3))
end

service_b = Endpoint.new("/b/users", "GET").tap do |ep|
  ep.push_callee(Callee.new("ServiceB.list", line: 3))
end

expected_endpoints = [
  service_a,
  service_b,
]

FunctionalTester.new("fixtures/crystal/marten_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"           => YAML::Any.new(base_paths),
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_marten"),
}).perform_tests
