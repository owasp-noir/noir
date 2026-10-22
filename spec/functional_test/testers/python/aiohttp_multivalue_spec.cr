require "../../func_spec.cr"

# Regression test: aiohttp MultiDict/CIMultiDict expose `getall`/`getone`
# for repeated keys. The param extractor previously matched only `.get(`.
expected_endpoints = [
  Endpoint.new("/items", "GET", [
    Param.new("tag", "", "query"),
    Param.new("kind", "", "query"),
    Param.new("X-Trace", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/python/aiohttp_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
