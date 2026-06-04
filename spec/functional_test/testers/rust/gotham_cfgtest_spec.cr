require "../../func_spec.cr"

# Routes registered inside a `#[cfg(test)] mod tests { ... }` block are
# unit-test scaffolding, not production endpoints. The gotham analyzer now
# gates them out via the shared cfg(test) region scan (like axum/loco/tide/
# salvo), so only the production route surfaces.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/rust/gotham_cfgtest/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_gotham"),
}).perform_tests
