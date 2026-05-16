require "../../func_spec.cr"

# Regression test for the --include-callee feature: Flask analyzer must
# emit 1-hop callees observed inside each handler body, deduped and capped.
# Builtins (print/len/range/...) and Python dunder methods are filtered;
# framework calls like `jsonify` are kept on purpose because they tell a
# reviewer how the endpoint shapes its output.
#
# Imported helper callees (build_user_query, run_sql_query, log_audit,
# notify_admin) resolve to their definitions in helpers.py; framework
# calls like `jsonify` stay unresolved (no Python definition reachable
# from the project root) and keep their call-site location.
helpers_path = "./spec/functional_test/fixtures/python/flask_callees/helpers.py"

expected_endpoints = [
  # POST /users — exercises every callee in the handler plus dedup
  # (`run_sql_query` is only called once but `request.form[...]` is a
  # subscript, not a call, so it must not show up).
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("build_user_query", helpers_path, 1))
    ep.push_callee(Callee.new("run_sql_query", helpers_path, 5))
    ep.push_callee(Callee.new("log_audit", helpers_path, 14))
    ep.push_callee(Callee.new("notify_admin", helpers_path, 10))
    ep.push_callee(Callee.new("jsonify"))
  end,

  # GET /orders/<order_id> — same helpers as POST /users (verifies the
  # callee list is per-handler, not deduped across endpoints).
  Endpoint.new("/orders/<order_id>", "GET").tap do |ep|
    ep.push_callee(Callee.new("build_user_query", helpers_path, 1))
    ep.push_callee(Callee.new("run_sql_query", helpers_path, 5))
    ep.push_callee(Callee.new("jsonify"))
  end,

  # GET /healthz — single callee, confirms small handlers still get
  # populated rather than left empty.
  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("jsonify"))
  end,

  # GET /many — handler has 12 unique calls; spec asserts the first 10
  # surface (c1..c10) and that jsonify (the 13th call in source order)
  # gets dropped under Callee::MAX_PER_ENDPOINT. Functional presence
  # check; the strict 10-count guarantee lives in the model unit test.
  Endpoint.new("/many", "GET").tap do |ep|
    ep.push_callee(Callee.new("c1"))
    ep.push_callee(Callee.new("c10"))
  end,
]

FunctionalTester.new("fixtures/python/flask_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
