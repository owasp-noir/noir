require "../../func_spec.cr"

# Regression test for --include-callee on Iris (#1366). Iris uses
# `.Party(...)` for route groups; the route extractor handles that via
# `group_method: "Party"`, and callee wiring is identical to Gin/Hertz
# (with the same ANY-verb fan-out branch).
#
# Coverage:
#   - POST /users   — named handler `createUser` in sibling
#                     `handlers.go`; cross-file lookup.
#   - GET /healthz  — inline closure in main.go.
#   - GET /profile  — second named handler in handlers.go.
#
# This fixture does not exercise the ANY-route fan-out path; the
# callee push lives in both branches of iris.cr, but adding an
# `.Any("/x", h)` here would just re-state the same assertion N times.
helpers_path = "./spec/functional_test/fixtures/go/iris_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("ctx.PostValue", line: 8))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.JSON", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("ctx.JSON", line: 11))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.JSON", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/iris_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
