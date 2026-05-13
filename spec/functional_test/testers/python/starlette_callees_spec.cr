require "../../func_spec.cr"

# Regression test for --include-callee on Starlette. The analyzer uses
# a Route()/Mount() scan, then resolves the referenced handler function
# to attach 1-hop callees to every emitted endpoint/method.
search_params = [
  Param.new("q", "", "query"),
  Param.new("X-Token", "", "header"),
]

expected_endpoints = [
  Endpoint.new("/users/{user_id}", "POST", [
    Param.new("user_id", "", "path"),
    Param.new("body", "", "json"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.json", line: 7))
    ep.push_callee(Callee.new("save_user", line: 9))
    ep.push_callee(Callee.new("audit_log", line: 10))
    ep.push_callee(Callee.new("JSONResponse", line: 11))
  end,

  Endpoint.new("/health", "GET").tap do |ep|
    ep.push_callee(Callee.new("Response", line: 15))
  end,

  Endpoint.new("/search", "GET", search_params).tap do |ep|
    ep.push_callee(Callee.new("request.query_params.get", line: 19))
    ep.push_callee(Callee.new("request.headers.get", line: 20))
    ep.push_callee(Callee.new("run_search", line: 21))
    ep.push_callee(Callee.new("JSONResponse", line: 22))
  end,

  Endpoint.new("/search", "POST", search_params).tap do |ep|
    ep.push_callee(Callee.new("request.query_params.get", line: 19))
    ep.push_callee(Callee.new("request.headers.get", line: 20))
    ep.push_callee(Callee.new("run_search", line: 21))
    ep.push_callee(Callee.new("JSONResponse", line: 22))
  end,

  Endpoint.new("/api/items", "GET", [
    Param.new("session", "", "cookie"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.cookies.get", line: 26))
    ep.push_callee(Callee.new("fetch_items", line: 27))
    ep.push_callee(Callee.new("audit_log", line: 28))
    ep.push_callee(Callee.new("JSONResponse", line: 29))
  end,
]

FunctionalTester.new("fixtures/python/starlette_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
