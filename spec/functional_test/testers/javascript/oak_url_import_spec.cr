require "../../func_spec.cr"

# Legacy `https://deno.land/x/oak@vX.Y.Z/mod.ts` import style, plus the
# `new Router({ prefix: '/x' })` constructor recipe.
expected_endpoints = [
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/api/v1/items/:itemId", "GET", [
    Param.new("itemId", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/oak_url_import/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
