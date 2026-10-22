require "../../func_spec.cr"

# A `#` on a line inside a multi-line triple-quoted string is not a
# comment. Treating it as one left the decorator's `(` unbalanced, so the
# decorator joined past its own close and the route was dropped.
expected_endpoints = [
  Endpoint.new("/one", "GET", [
    Param.new("q", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/fastapi_docstring_comment/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
