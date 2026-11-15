require "../../func_spec.cr"

# Re-exported routers must resolve to their declaring module so every
# include_router prefix survives, including the /api -> /v1 -> users chain.
expected_endpoints = [
  Endpoint.new("/api/relative/whoami", "GET"),
  Endpoint.new("/api/alias/whoami", "GET"),
  Endpoint.new("/api/absolute/whoami", "GET"),
  Endpoint.new("/api/two-hop/whoami", "GET"),
  Endpoint.new("/api/direct/whoami", "GET"),
  Endpoint.new("/api/v1/users/whoami", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_reexported_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
