require "../../func_spec.cr"

# Routes registered on struct fields typed `*echo.Echo` / `*echo.Group`
# (#3591), an embedded `*echo.Echo` included; an `*http.Client` field's
# `Get` is not one.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/embedded", "POST"),
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path"), Param.new("fields", "", "query")]),
]

FunctionalTester.new("fixtures/go/echo_router_field/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
