require "../../func_spec.cr"

# Regression test: Starlette QueryParams/Headers expose `getlist("key")` for
# repeated keys. The param extractor previously matched only `.get(`.
expected_endpoints = [
  Endpoint.new("/filter", "GET", [
    Param.new("tag", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/starlette_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
