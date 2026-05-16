require "../../func_spec.cr"

# Regression test for --include-callee on http4k (#1366). http4k's
# routing idiom is `"/x" bind GET to handler` (Kotlin infix), so
# the handler "body" is whatever expression sits on the RHS of `to`
# — usually a lambda, occasionally a function reference. The route
# extractor already passes that RHS into a handler scanner for
# parameter signals; callee extraction reuses the same RHS via
# `KotlinCalleeExtractor.callees_in_lambda` with `skip_routing: false`
# (http4k doesn't have Ktor-style nested routing DSL inside a
# handler body, so the skip filter would only cause false negatives).
#
# Coverage:
#   - POST /users    — selector-on-identifier (`req.query`),
#                      bare-static (`UserService.save`,
#                      `AuditLog.write`), and bare constructor-like
#                      (`Response`) call shapes.
#   - GET  /profile  — bare unqualified call (`buildProfile`).
#   - GET  /legacy   — chained-on-call (`getLegacy().toString()`)
#                      drops the outer `toString` and keeps only
#                      the inner `getLegacy`.
expected_endpoints = [
  Endpoint.new("/users", "POST", [Param.new("name", "", "query")]).tap do |ep|
    ep.push_callee(Callee.new("req.query", line: 13))
    ep.push_callee(Callee.new("UserService.save", line: 14))
    ep.push_callee(Callee.new("AuditLog.write", line: 15))
    ep.push_callee(Callee.new("Response", line: 16))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", line: 20))
    ep.push_callee(Callee.new("AuditLog.write", line: 21))
    ep.push_callee(Callee.new("Response", line: 22))
  end,

  Endpoint.new("/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 26))
    ep.push_callee(Callee.new("getLegacy", line: 27))
    ep.push_callee(Callee.new("Response", line: 28))
  end,
]

FunctionalTester.new("fixtures/kotlin/http4k_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
