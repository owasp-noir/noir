require "../../func_spec.cr"

# A `MethodRouter` held in a `let` or returned by a helper fn keeps its
# verbs, and `trace(h)` is TRACE.
expected_endpoints = [
  Endpoint.new("/trace", "TRACE"),
  Endpoint.new("/submit", "POST"),
  Endpoint.new("/both", "GET"),
  Endpoint.new("/both", "PUT"),
  Endpoint.new("/login", "POST"),
  Endpoint.new("/logout", "GET"),
  Endpoint.new("/logout", "DELETE"),
]

FunctionalTester.new("fixtures/rust/axum_method_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
