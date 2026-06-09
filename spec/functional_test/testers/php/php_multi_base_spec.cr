require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/php/php_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/php/php_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/index.php", "GET", [Param.new("a", "", "query")]),
  Endpoint.new("/admin.php", "GET", [Param.new("b", "", "query")]),
]

FunctionalTester.new("fixtures/php/php_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
