require "../../func_spec.cr"

# Fiber analyzer issues:
# 1. c.Params("id") for path parameter extraction is not detected
#    (analyzer only checks .Query() and .FormValue())
# 2. c.BodyParser for JSON body parsing is not detected
#
# Expected: /users/:id with id "path" param, /data with JSON body indicator
expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/data", "POST"),
]

UncoveredFunctionalTester.new("fixtures/go/fiber/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
