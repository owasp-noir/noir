require "../../func_spec.cr"

# Regression test for --include-callee on Sanic. Verifies decorator-based
# async handlers populate Endpoint.callees with both bare identifiers
# (save_user, audit_log, json) and dotted-attribute calls
# (request.form.get) — same shape as the Flask coverage.
expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.form.get"))
    ep.push_callee(Callee.new("save_user"))
    ep.push_callee(Callee.new("audit_log"))
    ep.push_callee(Callee.new("json"))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("json"))
  end,
]

FunctionalTester.new("fixtures/python/sanic_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
