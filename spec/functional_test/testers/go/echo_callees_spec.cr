require "../../func_spec.cr"

# Regression test for --include-callee on Echo (#1366). Same shape as
# the Gin coverage:
#
#   - POST /users   — named handler `createUser` in sibling
#                     `handlers.go`; exercises the cross-file lookup.
#   - GET /healthz  — inline closure handler in main.go.
#   - GET /profile  — second named handler in handlers.go to confirm
#                     per-handler scoping.
#
# Echo's existing file-local param extraction (FormValue/QueryParam/
# Header.Get) does not follow into sibling files, so the form param
# for POST /users isn't surfaced — params and callees stay orthogonal.
expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("c.FormValue", line: 8))
    ep.push_callee(Callee.new("saveUser", line: 9))
    ep.push_callee(Callee.new("auditLog", line: 10))
    ep.push_callee(Callee.new("c.JSON", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("c.JSON", line: 11))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", line: 15))
    ep.push_callee(Callee.new("auditLog", line: 16))
    ep.push_callee(Callee.new("c.JSON", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/echo_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
