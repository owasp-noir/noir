require "../../func_spec.cr"

expected_endpoints = [
  # `method` defaults to GET.
  Endpoint.new("/v1/products/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
    Param.new("Authorization", "", "header"),
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/v1/orders", "POST"),
]

FunctionalTester.new("fixtures/specification/krakend/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
