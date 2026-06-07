require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/java/struts2_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/java/struts2_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/root", "ANY"),
  Endpoint.new("/a-extra/included", "ANY"),
  Endpoint.new("/b/root", "ANY"),
  Endpoint.new("/b-extra/included", "ANY"),
]

FunctionalTester.new("fixtures/java/struts2_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
