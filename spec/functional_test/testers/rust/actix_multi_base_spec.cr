require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/rust/actix_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/rust/actix_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/list", "GET"),
  Endpoint.new("/a/status", "GET"),
  Endpoint.new("/b/list", "GET"),
  Endpoint.new("/b/status", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests

# The parent of both crates scanned as one base: each crate's mounts must
# stay with its own handlers (#3121).
FunctionalTester.new("fixtures/rust/actix_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
