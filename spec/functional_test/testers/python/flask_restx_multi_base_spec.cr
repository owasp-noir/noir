require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/python/flask_restx_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/python/flask_restx_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/users/items", "GET"),
  Endpoint.new("/b/users/items", "GET"),
]

FunctionalTester.new("fixtures/python/flask_restx_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("python_flask"),
}).perform_tests
