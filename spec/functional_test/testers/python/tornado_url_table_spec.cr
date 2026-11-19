require "../../func_spec.cr"

# The route table lives in a `urls.py` that imports only handler classes and
# never names `tornado`; `app.py` hands it to `Application.__init__`. A list
# whose handler is defined outside any Tornado module is not a route table.
expected_endpoints = [
  Endpoint.new("/p01-foo", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/p01-foo", "POST", [Param.new("name", "", "form")]),
  Endpoint.new("/p02-bar/(\\d+)", "GET", [Param.new("bar_id", "", "path")]),
]

FunctionalTester.new("fixtures/python/tornado_url_table/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
