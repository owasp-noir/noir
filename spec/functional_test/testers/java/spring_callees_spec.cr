require "../../func_spec.cr"

# Regression test for --include-callee on Spring (#1366). Spring is
# the first JVM analyzer to grow callees, and the shape mirrors the
# Python/Go path: a tree-sitter parse already produced for route and
# parameter extraction is reused to walk the matching
# `method_declaration` body for 1-hop `method_invocation` nodes.
#
# Cross-file definition resolution (e.g. `service.save` →
# `UserServiceImpl.save`) is intentionally out of scope for this
# first cut; `Callee#path` therefore points at the call site, matching
# the honest scope on every other analyzer.
#
# Coverage:
#   - POST /api/users/        — bare static (`AuditLog.write`) and
#                               selector-on-identifier
#                               (`service.save`) receivers.
#   - GET  /api/users/profile — `this.foo` receiver shape; the
#                               unambiguous same-file
#                               `buildProfile` declaration resolves
#                               to its definition line, while
#                               `AuditLog.write` (qualified
#                               non-`this`) stays at the call site.
#   - GET  /api/orders/legacy — chained-on-call (`getLegacy().toString()`)
#                               drops the outer `toString` and keeps
#                               only the inner `getLegacy`, matching
#                               the Python/Go chained-call noise filter.
expected_endpoints = [
  Endpoint.new("/api/users/", "POST").tap do |ep|
    ep.push_callee(Callee.new("service.save", line: 20))
    ep.push_callee(Callee.new("AuditLog.write", line: 21))
  end,

  Endpoint.new("/api/users/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 32))
    ep.push_callee(Callee.new("AuditLog.write", line: 28))
  end,

  Endpoint.new("/api/orders/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 13))
    ep.push_callee(Callee.new("getLegacy", line: 17))
  end,
]

FunctionalTester.new("fixtures/java/spring_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
