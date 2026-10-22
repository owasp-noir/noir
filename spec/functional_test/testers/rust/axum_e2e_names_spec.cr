require "../../func_spec.cr"

# `e2e` is also "end-to-end encryption" (Matrix-style servers), so
# `src/api/e2e_keys/` and `crates/e2e-encryption/` serve real routes. Only
# the whole `e2e` / `playwright` segment (optionally `-test(s)` / `_test(s)`)
# is a test harness.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
  Endpoint.new("/e2e/keys/upload", "GET"),
  Endpoint.new("/e2e/encrypt", "GET"),
]

FunctionalTester.new("fixtures/rust/axum_e2e_names/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
