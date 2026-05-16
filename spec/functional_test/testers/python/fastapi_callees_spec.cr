require "../../func_spec.cr"

# Regression test for --include-callee on FastAPI. Exercises four
# distinct emit paths:
#
#   1. POST /users          — straight @app.post with bare-identifier
#                              callees (save_user, audit_log).
#   2. GET /healthz         — no calls in the body; confirms empty
#                              callees stay empty.
#   3. GET /profile         — stacked decorators (@app.get +
#                              @auth_required + @rate_limit(10)). The
#                              pre-fix code assumed def was at
#                              `index + 1` and silently emitted zero
#                              callees here.
#   4. DELETE /orders/{...} — blank line + comment between the route
#                              decorator and the def. Same fragility,
#                              same fix path.
#   5. GET /reports         — @api.get on an APIRouter declared in
#                              a separate file; locks in that the
#                              include_router emit branch also pushes
#                              callees.
db_path = "./spec/functional_test/fixtures/python/fastapi_callees/db.py"
main_path = "./spec/functional_test/fixtures/python/fastapi_callees/main.py"

expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("save_user", db_path, 1))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("build_status", main_path, 16))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("save_user", db_path, 1))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  Endpoint.new("/orders/{order_id}", "DELETE").tap do |ep|
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  Endpoint.new("/reports", "GET").tap do |ep|
    ep.push_callee(Callee.new("db.fetch_report", db_path, 9))
  end,
]

FunctionalTester.new("fixtures/python/fastapi_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
