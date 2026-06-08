require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/java/struts2_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/java/struts2_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-package/package-annotated", "ANY"),
  Endpoint.new("/b-package/package-annotated", "ANY"),
  Endpoint.new("/a-extra/included", "ANY"),
  Endpoint.new("/b-extra/included", "ANY"),
]

a_root = Endpoint.new("/a/root", "ANY")
a_root.push_callee(Callee.new("aService.load"))
expected_endpoints << a_root

b_root = Endpoint.new("/b/root", "ANY")
b_root.push_callee(Callee.new("bService.load"))
expected_endpoints << b_root

FunctionalTester.new("fixtures/java/struts2_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"           => YAML::Any.new(base_paths),
  "include_callee" => YAML::Any.new(true),
}).perform_tests
