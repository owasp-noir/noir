require "../../func_spec.cr"

# Regression test: Tornado RequestHandler multi-value / scoped accessors
# (`get_query_argument(s)`, `get_body_arguments`, `get_secure_cookie`) were
# previously missed; only `get_argument(s)` / `get_body_argument` / `get_cookie`
# were handled.
expected_endpoints = [
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("tag", "", "query"),
    Param.new("user", "", "cookie"),
  ]),
  Endpoint.new("/tags", "POST", [
    Param.new("id", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/python/tornado_multivalue/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
