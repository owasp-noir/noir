require "../../func_spec.cr"

# Regression test for --include-callee on GoFrame (Gf, #1366). Gf
# uses three route shapes; this fixture exercises two of them plus
# the closure-scoped group flavor:
#
#   - GET /users         — `s.BindHandler("/users", createUser)`. Gf's
#                          BindHandler accepts any HTTP method and
#                          gf.cr folds the resulting "ALL" verb down to
#                          GET. Callees come from `createUser` in
#                          sibling `handlers.go`. The body also
#                          contains `name.String()` nested inside
#                          `saveUser(...)`, so we get a 5-callee list —
#                          locks in that nested-call expressions still
#                          surface their 1-hop callees.
#   - GET /healthz       — `s.BindHandler("/healthz", func(r ...){...})`,
#                          inline closure in main.go.
#   - GET /api/profile   — `s.Group("/api", func(group ...){
#                          group.GET("/profile", listProfile) })`.
#                          Locks in the closure-scoped group prefix
#                          (`/api`) + named handler from sibling file.
helpers_path = "./spec/functional_test/fixtures/go/gf_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "GET").tap do |ep|
    ep.push_callee(Callee.new("r.GetQuery", line: 8))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("name.String", line: 9))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("r.Response.Write", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("r.Response.Write", line: 12))
  end,

  Endpoint.new("/api/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("r.Response.Write", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/gf_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
