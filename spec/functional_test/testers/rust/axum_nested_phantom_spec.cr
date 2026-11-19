require "../../func_spec.cr"

# Routers nested inside a router that is itself nested exist only at their
# full prefix. The endpoint count pins the absence of the shorter copies
# (`/api/`, `/api/stats`, `/x/leaf`, `/users/list`, `/reports/report`).
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/users/", "GET"),
  Endpoint.new("/api/users/", "POST"),
  Endpoint.new("/api/admin/stats", "GET"),
  Endpoint.new("/deep/x/leaf", "GET"),
  Endpoint.new("/v2/users/list", "GET"),
  Endpoint.new("/v2/reports/report", "GET"),
]

FunctionalTester.new("fixtures/rust/axum_nested_phantom/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
}).perform_tests
