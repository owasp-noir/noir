require "../../func_spec.cr"

# Regression test for --include-callee on aiohttp. Routes use the
# RouteTableDef decorator form; the analyzer already had the handler
# body in hand at emit time, so wiring is a one-liner — this spec
# locks the per-endpoint scope (web.json_response shows up on both
# routes, save_order only on /orders).
app_path = "./spec/functional_test/fixtures/python/aiohttp_callees/app.py"
db_path = "./spec/functional_test/fixtures/python/aiohttp_callees/db.py"

expected_endpoints = [
  Endpoint.new("/orders", "POST").tap do |ep|
    ep.push_callee(Callee.new("request.json", app_path, 9))
    ep.push_callee(Callee.new("save_order", db_path, 1))
    ep.push_callee(Callee.new("web.json_response", app_path, 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("web.json_response", app_path, 16))
  end,
]

FunctionalTester.new("fixtures/python/aiohttp_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
