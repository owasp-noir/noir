require "../../func_spec.cr"

# Regression test for --include-callee on go-zero (#1366). Gozero
# handles two route declaration styles, and only one of them gets
# callees:
#
#   - `.go` verb routes (`server.Get("/x", h)`) — picked up by
#     `extract_routes`, callee extraction wires identically to
#     Gin/Beego/etc.
#   - `.api` DSL routes (`get /x (Request)` inside `service` blocks)
#     — gozero's own templating language, NOT Go. There's no Go
#     call_expression to extract a 1-hop graph from, so the spec
#     locks in that `.api`-declared routes emit with an EMPTY callee
#     list rather than failing or surfacing junk.
#
# Coverage:
#   - POST /users   — named handler `createUser` in sibling
#                     `handlers.go`.
#   - GET /healthz  — inline closure in main.go.
#   - GET /profile  — second named handler in handlers.go.
#   - GET /legacy   — declared in `legacy.api` (DSL); zero callees.
helpers_path = "./spec/functional_test/fixtures/go/gozero_callees/helpers.go"

expected_endpoints = [
  Endpoint.new("/users", "POST").tap do |ep|
    ep.push_callee(Callee.new("r.FormValue", line: 10))
    ep.push_callee(Callee.new("saveUser", helpers_path, 3))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("httpx.OkJson", line: 13))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("httpx.OkJson", line: 19))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", helpers_path, 10))
    ep.push_callee(Callee.new("auditLog", helpers_path, 7))
    ep.push_callee(Callee.new("httpx.OkJson", line: 19))
  end,

  # No callees expected — `.api` files are a non-Go DSL, callees stay empty.
  Endpoint.new("/legacy", "GET"),
]

FunctionalTester.new("fixtures/go/gozero_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
