require "../../func_spec.cr"

# Two Midway apps, each with its own `globalPrefix`: a prefix applies only to
# the controllers under its own package.json.
expected_endpoints = [
  Endpoint.new("/admin-api/admin/status", "GET", [] of Param),
  Endpoint.new("/shop-api/shop/status", "GET", [] of Param),
]

FunctionalTester.new("fixtures/typescript/midway_monorepo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
