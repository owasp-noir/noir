require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/go/gin_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/go/gin_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-only", "GET"),
  Endpoint.new("/b-only", "GET"),
  Endpoint.new("/assets/a.txt", "GET"),
  Endpoint.new("/assets/b.txt", "GET"),
]

FunctionalTester.new("fixtures/go/gin_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
