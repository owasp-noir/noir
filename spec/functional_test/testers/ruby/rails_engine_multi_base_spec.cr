require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/ruby/rails_engine_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/ruby/rails_engine_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-engine", "GET"),
  Endpoint.new("/a-engine/posts", "GET"),
  Endpoint.new("/b-engine", "GET"),
  Endpoint.new("/b-engine/posts", "GET"),
]

FunctionalTester.new("fixtures/ruby/rails_engine_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
