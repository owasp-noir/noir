require "../../func_spec.cr"

# Regression test for --include-callee on Chi (#1366). Chi uses
# closure-scoped routing (`r.Route("/prefix", func(r chi.Router){...})`)
# so a verb call's `route.line` lives inside a nested closure body.
# `GoCalleeExtractor.callees_for_routes` walks the full file's AST and
# filters by row, so nested call_expressions resolve normally.
#
# Coverage:
#   - POST /users    — named handler `createUser` in sibling
#                      `handlers.go`; cross-file lookup.
#   - GET /healthz   — inline `func(w http.ResponseWriter, ...)` in
#                      main.go.
#   - GET /profile/  — `r.Route("/profile", func(r chi.Router){
#                      r.Get("/", listProfile) })`; locks in that
#                      callees attach to the inner verb call inside a
#                      Chi closure-scoped group. Trailing slash matches
#                      Chi extractor's path joining.
#
# Mount-expanded routes (`r.Mount("/admin", adminRouter())`) do NOT
# get callees in this first cut — `analyze_router_function` runs its
# own isolated route walk and would need separate wiring. Tracking
# that as a follow-up in #1366.
helpers_path = "./spec/functional_test/fixtures/go/chi_callees/helpers.go"

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

  Endpoint.new("/profile/", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("w.Write", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/chi_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
