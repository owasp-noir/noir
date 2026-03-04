require "../../func_spec.cr"

# Chi analyzer does not support OPTIONS and HEAD methods.
# The route regex pattern only includes GET|POST|PUT|DELETE|PATCH.
expected_endpoints = [
  Endpoint.new("/cors", "OPTIONS"),
  Endpoint.new("/ping", "HEAD"),
]

UncoveredFunctionalTester.new("fixtures/go/chi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
