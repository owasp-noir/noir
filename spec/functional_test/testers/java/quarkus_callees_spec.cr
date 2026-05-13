require "../../func_spec.cr"

# Regression test for --include-callee on Quarkus's JAX-RS-flavoured
# analyzer. Quarkus shares the JAX-RS extractor and should receive the
# same method-body callee coverage.
expected_endpoints = [
  Endpoint.new("/greetings/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("dry_run", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("validate", line: 20))
    ep.push_callee(Callee.new("service.save", line: 21))
    ep.push_callee(Callee.new("AuditLog.write", line: 22))
    ep.push_callee(Callee.new("Response.ok", line: 23))
  end,

  Endpoint.new("/greetings/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 29))
    ep.push_callee(Callee.new("AuditLog.write", line: 30))
    ep.push_callee(Callee.new("Response.ok", line: 31))
  end,
]

FunctionalTester.new("fixtures/java/quarkus_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
