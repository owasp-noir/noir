require "../../func_spec.cr"

# Performance regression: every router here is reachable through 2**24
# include paths. Configuring a router once per path never finishes; it is
# configured once per inherited prefix instead.
expected_endpoints = [
  Endpoint.new("/api/leaf", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_router_diamond/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
