require "../../func_spec.cr"

# Regression test for --include-callee on Javalin (#1366). Javalin
# runs on the lambda-DSL shape — `app.get("/x", ctx -> { ... })` —
# so callees come out of a Java `lambda_expression`'s body, not a
# `method_declaration`. The shared JVM lambda DSL extractor already
# locates that body for parameter scanning; callee extraction reuses
# it via `JavaCalleeExtractor.callees_in_lambda`.
#
# Coverage:
#   - POST /users    — selector-on-identifier (`ctx.queryParam`,
#                      `ctx.result`) and bare-static
#                      (`UserService.save`, `AuditLog.write`)
#                      receivers.
#   - GET  /profile  — bare unqualified call (`buildProfile`).
#   - GET  /legacy   — chained-on-call (`getLegacy().toString()`)
#                      drops the outer `toString` and keeps only
#                      the inner `getLegacy`.
expected_endpoints = [
  Endpoint.new("/users", "POST", [Param.new("name", "", "query")]).tap do |ep|
    ep.push_callee(Callee.new("ctx.queryParam", line: 10))
    ep.push_callee(Callee.new("UserService.save", line: 11))
    ep.push_callee(Callee.new("AuditLog.write", line: 12))
    ep.push_callee(Callee.new("ctx.result", line: 13))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", line: 17))
    ep.push_callee(Callee.new("AuditLog.write", line: 18))
    ep.push_callee(Callee.new("ctx.result", line: 19))
  end,

  Endpoint.new("/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 23))
    ep.push_callee(Callee.new("ctx.result", line: 24))
    ep.push_callee(Callee.new("getLegacy", line: 24))
  end,
]

FunctionalTester.new("fixtures/java/javalin_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
