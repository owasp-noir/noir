require "../../func_spec.cr"

# `<yyyy:year>` uses a converter registered with `register_converter`. Not
# being a builtin, `yyyy` was taken for Marten's name-first order and the
# endpoint declared a param named after the converter.
expected_endpoints = [
  Endpoint.new("/articles/<yyyy:year>/", "GET", [Param.new("year", "", "path")]),
  Endpoint.new("/posts/<int:pk>/", "GET", [Param.new("pk", "", "path")]),
]

FunctionalTester.new("fixtures/python/django_custom_converter/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
