require "../../func_spec.cr"

# Regression test for --include-callee on TypeScript LoopBack. LB4 handler
# bodies read from injected repository/service properties (`this.xRepository`)
# the same shape NestJS providers do, so callee extraction is scoped to the
# JavaScript-compatible method body the same way.
expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "body"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("this.validationService.validate", line: 6))
    ep.push_callee(Callee.new("this.userRepository.create", line: 7))
    ep.push_callee(Callee.new("AuditLog.write", line: 8))
    ep.push_callee(Callee.new("this.presenter.user", line: 9))
  end,

  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("include", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("this.userRepository.findById", line: 17))
    ep.push_callee(Callee.new("buildProfile", line: 18))
  end,
]

FunctionalTester.new("fixtures/typescript/loopback_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
