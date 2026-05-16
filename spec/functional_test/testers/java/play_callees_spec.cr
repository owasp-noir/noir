require "../../func_spec.cr"

# Regression test for --include-callee on Play Framework. Routes map
# to controller methods, so the analyzer attaches callees discovered
# in the referenced controller method body.
expected_endpoints = [
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
    Param.new("X-Token", "", "header"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request", line: 9))
    ep.push_callee(Callee.new("parseUser", line: 10))
    ep.push_callee(Callee.new("userService", line: 11))
    ep.push_callee(Callee.new("AuditLog.write", line: 12))
    ep.push_callee(Callee.new("ok", line: 13))
    ep.push_callee(Callee.new("Json.toJson", line: 13))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 17))
    ep.push_callee(Callee.new("AuditLog.write", line: 18))
    ep.push_callee(Callee.new("ok", line: 19))
  end,
]

FunctionalTester.new("fixtures/java/play_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
