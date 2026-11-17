require "../../func_spec.cr"

# `/status` (`deny all` before any `allow`) must not be reported.
expected_endpoints = [
  Endpoint.new("/metrics", "ANY"),
  Endpoint.new("/api/", "ANY"),
]

FunctionalTester.new("fixtures/specification/nginx_denied/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
