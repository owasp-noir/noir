require "../../func_spec.cr"

# Regression test for --include-callee on Sanic. Verifies decorator-based
# async handlers populate Endpoint.callees with both bare identifiers
# (save_user, audit_log, json) and dotted-attribute calls
# (request.form.get) — same shape as the Flask coverage.
app_path = "./spec/functional_test/fixtures/python/sanic_callees/app.py"
db_path = "./spec/functional_test/fixtures/python/sanic_callees/db.py"

expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.form.get", app_path, 10))
    ep.push_callee(Callee.new("save_user", db_path, 1))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
    ep.push_callee(Callee.new("json", app_path, 13))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("json", app_path, 18))
  end,
]

FunctionalTester.new("fixtures/python/sanic_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
