require "../../func_spec.cr"

# Regression test for --include-callee on Vert.x method-reference
# handlers. Regex route discovery still owns route matching; the
# analyzer resolves `this::handler` references to method bodies and
# attaches the handler's 1-hop callees.
expected_endpoints = [
  Endpoint.new("/users/:id", "POST").tap do |ep|
    ep.push_callee(Callee.new("ctx.pathParam", line: 19))
    ep.push_callee(Callee.new("parseUser", line: 20))
    ep.push_callee(Callee.new("service.save", line: 21))
    ep.push_callee(Callee.new("AuditLog.write", line: 22))
    ep.push_callee(Callee.new("ctx.response", line: 23))
  end,

  Endpoint.new("/orders/:id", "GET").tap do |ep|
    ep.push_callee(Callee.new("ctx.pathParam", line: 27))
    ep.push_callee(Callee.new("findOrder", line: 28))
    ep.push_callee(Callee.new("AuditLog.write", line: 29))
    ep.push_callee(Callee.new("ctx.response", line: 30))
  end,
]

FunctionalTester.new("fixtures/java/vertx_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
