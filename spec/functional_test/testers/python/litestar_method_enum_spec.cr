require "../../func_spec.cr"

# `http_method=` given as `HttpMethod.X` (list or scalar) sets the verb, and
# `Parameter(header=/cookie=/query=...)` sets the location and wire name.
expected_endpoints = [
  Endpoint.new("/b", "POST"),
  Endpoint.new("/b", "PUT"),
  Endpoint.new("/one", "DELETE"),
  Endpoint.new("/d", "GET", [
    Param.new("X-Token", "", "header"),
    Param.new("sid", "", "cookie"),
    Param.new("p", "", "query"),
    Param.new("limit", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/litestar_method_enum/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
