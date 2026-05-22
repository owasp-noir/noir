require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/things", "GET", [
    Param.new("q", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/things", "POST", [
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/reports", "GET", [
    Param.new("q", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/reports", "POST", [
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
  Endpoint.new("/profiles", "POST", [
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/sync-media", "PATCH", [
    Param.new("title", "", "json"),
    Param.new("state", "", "json"),
  ]),
  Endpoint.new("/external/reports", "GET", [
    Param.new("owner", "", "query"),
  ]),
  Endpoint.new("/external/reports", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/external/widgets/{widget_id}", "GET", [
    Param.new("X-Trace-ID", "", "header"),
    Param.new("widget_id", "", "path"),
  ]),
  Endpoint.new("/external/widgets/{widget_id}", "PATCH", [
    Param.new("status", "", "json"),
    Param.new("widget_id", "", "path"),
  ]),
  Endpoint.new("/external/profiles/{profile_id}", "GET", [
    Param.new("session", "", "cookie"),
    Param.new("profile_id", "", "path"),
  ]),
  Endpoint.new("/assets/*", "GET"),
]

FunctionalTester.new("fixtures/python/falcon/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
