require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/javascript/express_multi_base_alias/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/javascript/express_multi_base_alias/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/route-a", "GET"),
  Endpoint.new("/b/route-b", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_multi_base_alias/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
