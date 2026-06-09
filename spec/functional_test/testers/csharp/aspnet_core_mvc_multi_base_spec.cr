require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/csharp/aspnet_core_mvc_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/csharp/aspnet_core_mvc_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/Home/Index", "GET"),
  Endpoint.new("/b/Home/Index", "GET"),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
