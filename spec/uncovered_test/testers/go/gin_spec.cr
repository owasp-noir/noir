require "../../func_spec.cr"

# Gin analyzer issues:
# 1. c.Param("id") for path parameter extraction is not detected
#    (analyzer only checks Query, PostForm, GetHeader, Cookie)
# 2. c.ShouldBindJSON / c.BindJSON for JSON body parsing is not detected
#
# Expected: /users/:id with id "path" param, /data with JSON body indicator
expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/data", "POST"),
]

UncoveredFunctionalTester.new("fixtures/go/gin/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
