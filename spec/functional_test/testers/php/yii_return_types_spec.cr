require "../../func_spec.cr"

# Actions declaring a return type (`: string`, `: string|Response`,
# `: ?array`) are actions like any other; the protected one is not.
expected_endpoints = [
  Endpoint.new("/shop/index", "GET"),
  Endpoint.new("/shop/view", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/shop/cart", "GET"),
]

FunctionalTester.new("fixtures/php/yii_return_types/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
