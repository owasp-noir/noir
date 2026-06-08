require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/rust/salvo_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/rust/salvo_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/alpha/users", "POST", [
    Param.new("body", "", "json"),
    Param.new("X-Service-A", "", "header"),
  ]),
  Endpoint.new("/b/beta/users", "POST", [
    Param.new("body", "", "json"),
    Param.new("X-Service-B", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/rust/salvo_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"           => YAML::Any.new(base_paths),
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_salvo"),
}).perform_tests
