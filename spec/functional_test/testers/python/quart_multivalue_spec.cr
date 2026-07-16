require "../../func_spec.cr"

# Regression test: Quart/Werkzeug MultiDicts expose `getlist("key")` for
# repeated keys. The param extractor previously matched only `.get(`.
expected_endpoints = [
  Endpoint.new("/search", "GET", [
    Param.new("ids", "", "query"),
    Param.new("category", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/quart_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
