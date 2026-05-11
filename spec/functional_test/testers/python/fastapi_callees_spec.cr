require "../../func_spec.cr"

# Regression test for --include-callee on FastAPI. Decorator-based
# endpoints (`@app.get`/`@app.post`/…) now emit per-handler callees —
# verifies the `parse_code_block` step added at the emit site lands
# correctly and that bare-identifier calls (save_user, audit_log) get
# picked up.
expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("save_user", line: 9))
    ep.push_callee(Callee.new("audit_log", line: 10))
  end,

  Endpoint.new("/healthz", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
