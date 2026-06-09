require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/swift/hummingbird_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/swift/hummingbird_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/items", "GET"),
  Endpoint.new("/b/items", "GET"),
]

FunctionalTester.new("fixtures/swift/hummingbird_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("swift_hummingbird"),
}).perform_tests
