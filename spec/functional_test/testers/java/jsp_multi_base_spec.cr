require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/java/jsp_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/java/jsp_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a.jsp", "GET", [Param.new("a", "", "query")]),
  Endpoint.new("/b.jsp", "GET", [Param.new("b", "", "query")]),
]

FunctionalTester.new("fixtures/java/jsp_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
