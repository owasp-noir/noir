require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/", "GET", [] of Param),
  Endpoint.new("/users/profile/<user_id>", "GET", [
    Param.new("user_id", "", "path"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/users/search", "GET", [
    Param.new("query", "", "query"),
    Param.new("region", "", "query"),
  ]),
  Endpoint.new("/users/*", "GET", [] of Param),
  Endpoint.new("/", "GET", [] of Param),
  Endpoint.new("/generate", "GET", [
    Param.new("length", "", "query"),
  ]),
  Endpoint.new("/users/reports/", "GET", [] of Param),
  Endpoint.new("/users/reports/latest/<report_id>", "GET", [
    Param.new("report_id", "", "path"),
    Param.new("X-Api-Token", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/python/cherrypy/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
