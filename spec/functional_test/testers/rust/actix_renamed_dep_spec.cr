require "../../func_spec.cr"

# `package = "actix-web"` under a target-specific table is still the dependency:
# the detector reads what the crate gate reads.
expected_endpoints = [
  Endpoint.new("/hello", "GET"),
]

FunctionalTester.new("fixtures/rust/actix_renamed_dep/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_actix_web"),
}).perform_tests
