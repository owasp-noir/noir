require "../../func_spec.cr"

# `"$CONST/x"` and `"${Obj.CONST}/x"` templates resolve like `CONST + "/x"`,
# constants built from other constants resolve, and `Type.CONST` from
# another file is a route path. An unknown name keeps its placeholder.
expected_endpoints = [
  Endpoint.new("/api/v2/a-short", "GET"),
  Endpoint.new("/api/v2/b-braced", "GET"),
  Endpoint.new("/api/v2/c-concat", "GET"),
  Endpoint.new("/api/v1/d-object", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v2/admin/e-derived", "GET"),
  Endpoint.new("/api/v2/f-route/create", "POST"),
  Endpoint.new("/g-real/{id}/{UNKNOWN_SUFFIX}", "GET", [
    Param.new("id", "", "path"),
    Param.new("UNKNOWN_SUFFIX", "", "path"),
  ]),
  Endpoint.new("/api/v1", "GET"),
  Endpoint.new("/api/v1/h-cross-concat", "GET"),
  Endpoint.new("/local", "GET"),
  Endpoint.new("/local/items", "GET"),
  Endpoint.new("/local/items2", "GET"),
]

FunctionalTester.new("fixtures/kotlin/ktor_const_paths/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
