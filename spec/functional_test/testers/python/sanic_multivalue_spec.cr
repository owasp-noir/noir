require "../../func_spec.cr"

# Regression test: Sanic RequestParameters expose `getlist("key")` for
# repeated keys. The param extractor previously matched only `.get(`.
expected_endpoints = [
  Endpoint.new("/search", "GET", [
    Param.new("ids", "", "query"),
    Param.new("tag", "", "query"),
  ]),
  Endpoint.new("/bulk", "POST", [
    Param.new("names", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/python/sanic_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
