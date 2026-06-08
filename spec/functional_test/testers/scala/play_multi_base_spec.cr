require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/scala/play_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/scala/play_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/direct-a", "GET", [
    Param.new("X-A", "", "header"),
  ]),
  Endpoint.new("/a/from-a", "GET"),
  Endpoint.new("/nested-a/included-a", "GET", [
    Param.new("X-A", "", "header"),
  ]),
  Endpoint.new("/direct-b", "GET", [
    Param.new("X-B", "", "header"),
  ]),
  Endpoint.new("/b/from-b", "GET"),
  Endpoint.new("/nested-b/included-b", "GET", [
    Param.new("X-B", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/scala/play_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
}).perform_tests
