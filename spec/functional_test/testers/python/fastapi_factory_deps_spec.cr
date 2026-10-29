require "../../func_spec.cr"

# A dependency's own parameters are request parameters wherever FastAPI
# resolves it: a `Depends(...)` handler parameter, a decorator's
# `dependencies=[...]` (literal or a name bound to one), and a dependency
# defined inside the app factory (#3263).
x_token = [Param.new("x-token", "", "header")]
expected_endpoints = [
  Endpoint.new("/nested", "GET", x_token),
  Endpoint.new("/aliased", "GET", x_token),
  Endpoint.new("/direct", "GET", x_token),
  Endpoint.new("/literal", "GET", x_token),
  Endpoint.new("/open", "GET"),
  # `limiter = RateLimiter()` is no dependency; a later `Depends(...)` in
  # the file is not its value.
  Endpoint.new("/limited", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_factory_deps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
