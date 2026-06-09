require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/java/wicket_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/java/wicket_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-scanned/only-a", "GET"),
  Endpoint.new("/a-api/only-a", "GET"),
  Endpoint.new("/b-scanned/only-b", "GET"),
  Endpoint.new("/b-api/only-b", "GET"),
]

FunctionalTester.new("fixtures/java/wicket_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
