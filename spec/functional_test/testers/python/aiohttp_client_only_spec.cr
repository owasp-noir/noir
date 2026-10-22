require "../../func_spec.cr"

# A FastAPI router that imports only the aiohttp CLIENT is FastAPI's, not
# aiohttp's. aiohttp used to read its `@router.post("/signin")` as a route
# and emit it without the include_router prefix, a path that is never served.
expected_endpoints = [
  Endpoint.new("/api/v1/auths/signin", "POST"),
]

FunctionalTester.new("fixtures/python/aiohttp_client_only/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
