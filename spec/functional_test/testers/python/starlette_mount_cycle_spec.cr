require "../../func_spec.cr"

# Regression test: a list mounted under its own (rebound) name made the
# mount-prefix fixpoint grow forever, and a `[` in a comment left a route
# list open to EOF so the Mount line below it was read as nested inside it.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/internal/status", "GET"),
]

FunctionalTester.new("fixtures/python/starlette_mount_cycle/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
