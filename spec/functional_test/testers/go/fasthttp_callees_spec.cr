require "../../func_spec.cr"

# Regression test for --include-callee on fasthttp (#1366). Fasthttp
# extends `Analyzer` directly (not `GoEngine`), so the analyzer builds
# `file_contents` inline at analyze() entry and uses the module-level
# twins on `GoCalleeExtractor` (same shape as Chi and httprouter).
#
# Coverage:
#   - POST /users   — named handler `createUser` in sibling
#                     `handlers.go`; the body also contains a
#                     `string(ctx.FormValue("name"))` type-conversion
#                     wrap, locking in that the `string` builtin is
#                     filtered while `ctx.FormValue` still surfaces as
#                     a callee on its own.
#   - GET /healthz  — inline `func(ctx *fasthttp.RequestCtx)` closure
#                     handler in main.go.
#   - GET /profile  — second named handler in handlers.go.
helpers_path = "./spec/functional_test/fixtures/go/fasthttp_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("ctx.FormValue", line: 8))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.WriteString", line: 11))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("ctx.WriteString", line: 18))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("ctx.WriteString", line: 17))
  end,
]

FunctionalTester.new("fixtures/go/fasthttp_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
