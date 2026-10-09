require "../../func_spec.cr"

# A `(` in a trailing comment on a route decorator used to hold the
# decorator open, so the handler `def` was never found and the route
# was dropped.
expected_endpoints = [
  Endpoint.new("/a", "GET", [Param.new("qa", "", "query")]),
  Endpoint.new("/b", "POST", [Param.new("qb", "", "form")]),
]

FunctionalTester.new("fixtures/python/flask_decorator_comment/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
