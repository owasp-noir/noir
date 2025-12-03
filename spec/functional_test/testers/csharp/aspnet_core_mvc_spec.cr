require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/v2/Home/Index", "GET"),
  Endpoint.new("/Home/Index", "GET"),
  Endpoint.new("/api/v2/Home/About", "GET"),
  Endpoint.new("/Home/About", "GET"),
  Endpoint.new("/api/v2/Home/Save", "POST", [
    Param.new("name", "", "form"),
    Param.new("description", "", "form"),
  ]),
  Endpoint.new("/Home/Save", "POST", [
    Param.new("name", "", "form"),
    Param.new("description", "", "form"),
  ]),
  Endpoint.new("/api/v2/Home/Details/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/Home/Details/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/Users", "GET", [
    Param.new("traceId", "", "header"),
  ]),
  Endpoint.new("/api/Users/{id:int}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/Users", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/api/Users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/api/Users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("soft", "", "query"),
  ]),
  Endpoint.new("/admin/Dashboard", "GET"),
  Endpoint.new("/admin/reports/{year:int}/{month:int}", "GET", [
    Param.new("year", "", "path"),
    Param.new("month", "", "path"),
  ]),
  Endpoint.new("/admin/Notify", "POST", [
    Param.new("subject", "", "form"),
    Param.new("message", "", "form"),
    Param.new("sessionId", "", "cookie"),
  ]),
  Endpoint.new("/mapped/health", "GET"),
  Endpoint.new("/mapped/items/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("filter", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
    Param.new("sessionId", "", "cookie"),
  ]),
  Endpoint.new("/mapped/methods", "PUT"),
  Endpoint.new("/mapped/methods", "DELETE"),
  Endpoint.new("/mapped/rich", "GET", [
    Param.new("q", "", "query"),
    Param.new("X-Test", "", "header"),
    Param.new("cid", "", "cookie"),
  ]),
  Endpoint.new("/mapped/form", "POST", [
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/expression/null", "GET", [
    Param.new("intValue", "", "query"),
    Param.new("strValue", "", "query"),
    Param.new("boolValue", "", "query"),
  ]),
  Endpoint.new("/expression/nulldefault", "GET", [
    Param.new("intValue", "", "query"),
    Param.new("strValue", "", "query"),
    Param.new("boolValue", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
