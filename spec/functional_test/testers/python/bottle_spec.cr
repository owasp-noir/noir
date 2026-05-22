require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/ping", "GET", [
    Param.new("name", "", "query"),
    Param.new("age", "", "query"),
  ]),
  Endpoint.new("/admin", "GET", [
    Param.new("abcd_token", "", "cookie"),
  ]),
  Endpoint.new("/submit", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
    Param.new("User-Agent", "", "header"),
  ]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
  ]),
  Endpoint.new("/users/<id:int>", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/admin/dashboard", "GET", [
    Param.new("section", "", "query"),
  ]),
  Endpoint.new("/admin/reports/<report_id:int>", "POST", [
    Param.new("report_id", "", "path"),
    Param.new("title", "", "json"),
  ]),
  Endpoint.new("/api/admin/metrics/<metric_id:int>", "GET", [
    Param.new("metric_id", "", "path"),
    Param.new("window", "", "query"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/keyword/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("X-Login-Token", "", "header"),
  ]),
  Endpoint.new("/keyword/status/<status_id:int>", "GET", [
    Param.new("status_id", "", "path"),
    Param.new("region", "", "query"),
  ]),
  Endpoint.new("/bulk", "PUT", [
    Param.new("action", "", "json"),
  ]),
  Endpoint.new("/bulk", "PATCH", [
    Param.new("action", "", "json"),
  ]),
  Endpoint.new("/health", "GET", [
    Param.new("probe", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/python/bottle/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
