require "../../func_spec.cr"

# Regression test for --include-callee on Spark Java (#1366). Spark
# shares the JVM lambda-DSL extractor with Javalin — the handler
# body is a Java `lambda_expression`'s body, parsed once and walked
# for both parameters and callees.
#
# Coverage:
#   - POST /users    — selector-on-identifier (`req.queryParams`,
#                      `res.status`) and bare-static
#                      (`UserService.save`, `AuditLog.write`)
#                      receivers.
#   - GET  /profile  — bare unqualified call (`buildProfile`).
#   - GET  /legacy   — chained-on-call (`getLegacy().toString()`)
#                      drops the outer `toString` and keeps only
#                      the inner `getLegacy`.
expected_endpoints = [
  Endpoint.new("/users", "POST", [Param.new("name", "", "query")]).tap do |ep|
    ep.push_callee(Callee.new("req.queryParams", line: 8))
    ep.push_callee(Callee.new("UserService.save", line: 9))
    ep.push_callee(Callee.new("AuditLog.write", line: 10))
    ep.push_callee(Callee.new("res.status", line: 11))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("buildProfile", line: 16))
    ep.push_callee(Callee.new("AuditLog.write", line: 17))
  end,

  Endpoint.new("/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 22))
    ep.push_callee(Callee.new("getLegacy", line: 23))
  end,
]

FunctionalTester.new("fixtures/java/spark_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
