require "../../func_spec.cr"

# Mux analyzer issues:
# 1. Multiple methods on one route - only first method is detected
#    e.g., .Methods("GET", "POST") only detects GET
# 2. .Queries() constraint for query parameters is not detected
#    e.g., .Queries("type", "{type}", "page", "{page}")
#
# Expected: /multi with both GET and POST, /filter with query params
expected_endpoints = [
  Endpoint.new("/multi", "GET"),
  Endpoint.new("/multi", "POST"),
  Endpoint.new("/filter", "GET", [
    Param.new("type", "", "query"),
    Param.new("page", "", "query"),
  ]),
]

UncoveredFunctionalTester.new("fixtures/go/mux/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
