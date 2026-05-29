require "../../func_spec.cr"

# Regression test for --include-callee on Gorilla Mux (#1366). Mux uses
# the `r.HandleFunc("/x", h).Methods("GET")` chain — verb comes from
# the outer `.Methods(...)` call. The route extractor records
# `route.line` on the inner HandleFunc call_expression, so the
# row-keyed callee lookup matches it. Both inline-closure and named
# handler resolutions go through the same path.
#
# Coverage:
#   - POST /users   — `r.HandleFunc("/users", createUser).Methods("POST")`
#                     with named handler in sibling `handlers.go`.
#   - GET /healthz  — same chain shape with an inline closure handler
#                     in main.go.
#   - GET /profile  — second named handler in handlers.go.
#   - POST /builder-users
#                   — builder chain with named handler in handlers.go.
#   - GET /builder-healthz
#                   — builder chain with http.HandlerFunc inline handler.
helpers_path = "./spec/functional_test/fixtures/go/mux_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("r.FormValue", line: 8))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("w.Write", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("w.Write", line: 13))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("w.Write", line: 17))
  end,

  Endpoint.new("/builder-users", "POST").tap do |ep|
    ep.push_callee(Callee.new("r.FormValue"))
    ep.push_callee(Callee.new("saveUser"))
    ep.push_callee(Callee.new("auditLog"))
    ep.push_callee(Callee.new("w.Write"))
  end,

  Endpoint.new("/builder-healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("w.Write"))
  end,
]

FunctionalTester.new("fixtures/go/mux_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
