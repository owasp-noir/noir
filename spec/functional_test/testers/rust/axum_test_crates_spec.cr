require "../../func_spec.cr"

# Workspace test crates (`app-tests`, `tests-fuzz`, `playwright-tests`,
# `e2e_test`) are harnesses, not the app. `contests`, `latest` and the
# singular `test-app` merely look similar and stay.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
  Endpoint.new("/contests", "GET"),
  Endpoint.new("/latest", "GET"),
  Endpoint.new("/test-app", "GET"),
]

FunctionalTester.new("fixtures/rust/axum_test_crates/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
