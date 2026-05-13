require "../../func_spec.cr"

# Regression test for --include-callee on TypeScript NestJS. Method
# signatures may contain TS annotations; callee extraction is scoped to
# the JavaScript-compatible method body.
expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("body", "", "body"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("this.authService.actor", line: 7))
    ep.push_callee(Callee.new("this.usersService.create", line: 8))
    ep.push_callee(Callee.new("AuditLog.write", line: 9))
    ep.push_callee(Callee.new("this.presenter.user", line: 11))
  end,

  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("include", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("this.usersService.findOne", line: 16))
    ep.push_callee(Callee.new("buildProfile", line: 18))
  end,
]

FunctionalTester.new("fixtures/typescript/nestjs_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
