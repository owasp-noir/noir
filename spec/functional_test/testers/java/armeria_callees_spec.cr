require "../../func_spec.cr"

# Regression test for --include-callee on Armeria annotated services.
# Builder-chain routes are regex-only and have no handler body here;
# annotated services already expose the method node and can provide
# 1-hop callees.
expected_endpoints = [
  Endpoint.new("/annotated/users/{userId}", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("Content-Type", "", "header"),
    Param.new("userId", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("validate", line: 17))
    ep.push_callee(Callee.new("service.save", line: 18))
    ep.push_callee(Callee.new("AuditLog.write", line: 19))
    ep.push_callee(Callee.new("HttpResponse.of", line: 20))
  end,

  Endpoint.new("/annotated/users/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 25))
    ep.push_callee(Callee.new("AuditLog.write", line: 26))
    ep.push_callee(Callee.new("HttpResponse.of", line: 27))
  end,
]

FunctionalTester.new("fixtures/java/armeria_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
