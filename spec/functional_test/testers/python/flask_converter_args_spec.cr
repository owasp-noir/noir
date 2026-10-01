require "../../func_spec.cr"

# `<int(signed=True):num>` and `<any(about, help):page>` are Werkzeug
# converters with arguments. The `(...)` made the converter fail the
# builtin-name check, so the whole placeholder resolved to no param at all.
expected_endpoints = [
  Endpoint.new("/n/<int(signed=True):num>", "GET", [Param.new("num", "", "path")]),
  Endpoint.new("/k/<any(about, help):page>", "GET", [Param.new("page", "", "path")]),
  Endpoint.new("/files/<path:subpath>", "GET", [Param.new("subpath", "", "path")]),
]

FunctionalTester.new("fixtures/python/flask_converter_args/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
