require "../../func_spec.cr"

# Regression test for --include-callee on Beego (#1366). Beego uses
# the verb-method shape (`web.Get("/x", h)` / `web.Post("/x", h)`)
# that `extract_routes` already recognises; only the wiring on the
# analyzer side was missing. Beego inherits from `GoEngine`, so it
# uses the engine helpers (`read_package_file_contents` +
# `collect_package_function_bodies`) — the same pattern as Goyave.
#
# Coverage:
#   - POST /users   — named handler `createUser` in sibling
#                     `handlers.go`; exercises a 2-level selector
#                     chain on the receiver (`ctx.Input.Query`,
#                     `ctx.Output.Body`), locking in that dotted
#                     callee names are reconstructed cleanly.
#   - GET /healthz  — inline `func(ctx *context.Context)` closure in
#                     main.go.
#   - GET /profile  — second named handler in handlers.go.
helpers_path = "./spec/functional_test/fixtures/go/beego_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("ctx.Input.Query", line: 8))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.Output.Body", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("ctx.Output.Body", line: 11))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.Output.Body", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/beego_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
