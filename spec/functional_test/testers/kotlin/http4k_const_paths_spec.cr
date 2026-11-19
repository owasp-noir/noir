require "../../func_spec.cr"

# `"$CONST/x"` and `"${Obj.CONST}/x"` templates resolve like `CONST + "/x"`,
# and `Paths.API` from another file is a route path.
expected_endpoints = [
  Endpoint.new("/v1/a-short", "GET"),
  Endpoint.new("/v1/b-concat", "GET"),
  Endpoint.new("/api", "GET"),
  Endpoint.new("/api/c-object", "PATCH"),
]

FunctionalTester.new("fixtures/kotlin/http4k_const_paths/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
