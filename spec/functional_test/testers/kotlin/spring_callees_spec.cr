require "../../func_spec.cr"

# Regression test for --include-callee on Spring (Kotlin) (#1366).
# Mirrors the Java Spring callees spec — both analyzers reuse a
# tree-sitter parse already produced for route and parameter
# extraction to walk the matching `function_declaration` body for
# 1-hop callees.
#
# Cross-file definition resolution is intentionally out of scope for
# this first cut; `Callee#path` therefore points at the call site,
# matching the honest scope on every other analyzer.
#
# Coverage:
#   - POST /api/users/        — bare-static (`AuditLog.write`) and
#                               selector-on-identifier
#                               (`service.save`) receivers.
#   - GET  /api/users/profile — `this.foo` receiver shape.
#   - GET  /api/orders/legacy — chained-on-call
#                               (`getLegacy().toString()`) drops the
#                               outer `toString` and keeps only the
#                               inner `getLegacy`.
expected_endpoints = [
  Endpoint.new("/api/users/", "POST").tap do |ep|
    ep.push_callee(Callee.new("service.save", line: 14))
    ep.push_callee(Callee.new("AuditLog.write", line: 15))
  end,

  Endpoint.new("/api/users/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 21))
    ep.push_callee(Callee.new("AuditLog.write", line: 22))
  end,

  Endpoint.new("/api/orders/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 13))
    ep.push_callee(Callee.new("getLegacy", line: 14))
  end,
]

FunctionalTester.new("fixtures/kotlin/spring_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
