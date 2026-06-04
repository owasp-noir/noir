require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("q", "", "query"),
    Param.new("lang", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Token", "", "header"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/api/items", "POST", [
    Param.new("name", "", "form"),
    Param.new("price", "", "form"),
  ]),
  Endpoint.new("/api/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
  ]),
  Endpoint.new("/about", "GET", [
    Param.new("source", "", "query"),
  ]),
  Endpoint.new("/external/reports/{report_id}", "GET", [
    Param.new("report_id", "", "path"),
    Param.new("include", "", "query"),
  ]),
  Endpoint.new("/ping", "GET", [
    Param.new("format", "", "query"),
  ]),
  Endpoint.new("/orders", "GET", [
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/orders", "POST", [
    Param.new("order_id", "", "json"),
  ]),
  # Multi-line @view_defaults(route_name="reports") — methods inherit the
  # class route_name even though the decorator's closing `)` is the line
  # directly above the class.
  Endpoint.new("/reports", "GET", [
    Param.new("scope", "", "query"),
  ]),
  Endpoint.new("/reports", "DELETE"),
  Endpoint.new("/assets/*", "GET"),
]

FunctionalTester.new("fixtures/python/pyramid/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
