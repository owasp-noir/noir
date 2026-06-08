require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/python/sanic_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/python/sanic_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/items/a-only", "GET"),
  Endpoint.new("/b/items/b-only", "GET"),
]

FunctionalTester.new("fixtures/python/sanic_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("python_sanic"),
}).perform_tests
