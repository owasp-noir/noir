require "../../func_spec.cr"

# Loco: explicit `Routes::new().prefix().add(...)` routes are reported,
# but a `#[cfg(test)]` route builder in the same controller is excluded.
expected_endpoints = [
  Endpoint.new("/api/notes", "GET"),
  Endpoint.new("/api/notes", "POST"),
]

FunctionalTester.new("fixtures/rust/loco_test_gate/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_loco"),
}).perform_tests
