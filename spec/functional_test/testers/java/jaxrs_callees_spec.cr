require "../../func_spec.cr"

# Regression test for --include-callee on vanilla JAX-RS resources.
# The shared JAX-RS extractor already walks each resource method, so
# it now returns 1-hop method invocations alongside route metadata.
expected_endpoints = [
  Endpoint.new("/users/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("dry_run", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("validate", line: 18))
    ep.push_callee(Callee.new("service.save", line: 19))
    ep.push_callee(Callee.new("AuditLog.write", line: 20))
    ep.push_callee(Callee.new("Response.ok", line: 21))
  end,

  Endpoint.new("/users/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 27))
    ep.push_callee(Callee.new("AuditLog.write", line: 28))
    ep.push_callee(Callee.new("Response.ok", line: 29))
  end,
]

FunctionalTester.new("fixtures/java/jaxrs_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
