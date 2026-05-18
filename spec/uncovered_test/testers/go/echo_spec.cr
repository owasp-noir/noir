require "../../func_spec.cr"

# Echo analyzer issues:
# 1. Commented-out routes are detected as false positives (// e.GET(...) still matches the regex)
# 2. c.Param("id") is classified as "json" param type instead of "path"
#
# Expected: only /users/:id with id as "path" param, no /old-route
expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
]

UncoveredFunctionalTester.new("fixtures/go/echo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
