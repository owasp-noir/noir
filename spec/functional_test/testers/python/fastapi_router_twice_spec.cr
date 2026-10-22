require "../../func_spec.cr"

# A router included more than once (two prefixes, or via a second parent)
# is served under every inclusion; only the first used to survive.
expected_endpoints = [
  Endpoint.new("/v1/ping", "GET"),
  Endpoint.new("/v2/ping", "GET"),
  Endpoint.new("/outer/ping", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_router_twice/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
