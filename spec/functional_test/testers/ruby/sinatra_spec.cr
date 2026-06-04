require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("query", "", "query"),
    Param.new("cookie1", "", "cookie"),
    Param.new("cookie2", "", "cookie"),
  ]),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/api/widgets", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/widgets", "POST", [
    Param.new("HTTP_X_TRACE_ID", "", "header"),
  ]),
  Endpoint.new("/api/route_widgets", "GET", [
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/api/route_widgets", "POST", [
    Param.new("token", "", "query"),
  ]),
  Endpoint.new("/api/verb_named/:post", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/v2/widgets", "GET", [
    Param.new("cursor", "", "query"),
  ]),
  Endpoint.new("/admin/dashboard", "GET", [
    Param.new("full", "", "query"),
  ]),
  Endpoint.new("/admin/audit", "GET", [
    Param.new("since", "", "query"),
  ]),
  Endpoint.new("/files/*", "GET", [
    Param.new("real", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/ruby/sinatra/", {
  :techs     => 1,
  :endpoints => 11,
}, expected_endpoints).perform_tests
