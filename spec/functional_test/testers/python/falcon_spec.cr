require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/things", "GET", [
    Param.new("q", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/things", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/things/{thing_id}", "GET", [
    Param.new("X-API-Key", "", "header"),
    Param.new("thing_id", "", "path"),
  ]),
  Endpoint.new("/things/{thing_id}", "DELETE", [
    Param.new("thing_id", "", "path"),
  ]),
  Endpoint.new("/things/{thing_id}/items", "GET", [
    Param.new("session", "", "cookie"),
    Param.new("thing_id", "", "path"),
  ]),
  Endpoint.new("/things/{thing_id}/items", "POST", [
    Param.new("body", "", "json"),
    Param.new("thing_id", "", "path"),
  ]),
  Endpoint.new("/auth", "POST", [
    Param.new("body", "", "json"),
    Param.new("auth_token", "", "cookie"),
  ]),
  Endpoint.new("/uploads/{name}", "PUT", [
    Param.new("body", "", "form"),
    Param.new("name", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/python/falcon/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
