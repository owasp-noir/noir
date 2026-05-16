require "../../func_spec.cr"

# Regression test for --include-callee on Starlette. The analyzer uses
# a Route()/Mount() scan, then resolves the referenced handler function
# to attach 1-hop callees to every emitted endpoint/method.
#
# Imported helper callees (save_user) resolve to their definition in
# helpers.py; unresolved bare names stay at the call site.
app_path = "./spec/functional_test/fixtures/python/starlette_callees/app.py"
helpers_path = "./spec/functional_test/fixtures/python/starlette_callees/helpers.py"

search_params = [
  Param.new("q", "", "query"),
  Param.new("X-Token", "", "header"),
]

expected_endpoints = [
  Endpoint.new("/users/{user_id}", "POST", [
    Param.new("user_id", "", "path"),
    Param.new("body", "", "json"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.json", app_path, 8))
    ep.push_callee(Callee.new("save_user", helpers_path, 1))
    ep.push_callee(Callee.new("audit_log", app_path, 11))
    ep.push_callee(Callee.new("JSONResponse", app_path, 12))
  end,

  Endpoint.new("/health", "GET").tap do |ep|
    ep.push_callee(Callee.new("Response", app_path, 16))
  end,

  Endpoint.new("/search", "GET", search_params).tap do |ep|
    ep.push_callee(Callee.new("request.query_params.get", app_path, 20))
    ep.push_callee(Callee.new("request.headers.get", app_path, 21))
    ep.push_callee(Callee.new("run_search", app_path, 22))
    ep.push_callee(Callee.new("JSONResponse", app_path, 23))
  end,

  Endpoint.new("/search", "POST", search_params).tap do |ep|
    ep.push_callee(Callee.new("request.query_params.get", app_path, 20))
    ep.push_callee(Callee.new("request.headers.get", app_path, 21))
    ep.push_callee(Callee.new("run_search", app_path, 22))
    ep.push_callee(Callee.new("JSONResponse", app_path, 23))
  end,

  Endpoint.new("/api/items", "GET", [
    Param.new("session", "", "cookie"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.cookies.get", app_path, 27))
    ep.push_callee(Callee.new("fetch_items", app_path, 28))
    ep.push_callee(Callee.new("audit_log", app_path, 29))
    ep.push_callee(Callee.new("JSONResponse", app_path, 30))
  end,
]

FunctionalTester.new("fixtures/python/starlette_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
