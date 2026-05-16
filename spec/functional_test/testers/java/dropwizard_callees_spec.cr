require "../../func_spec.cr"

# Regression test for --include-callee on Dropwizard resource classes.
# Dropwizard rides on the shared JAX-RS extractor, so its analyzer only
# needs to push the extractor-provided callees onto emitted endpoints.
expected_endpoints = [
  Endpoint.new("/hello/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("dry_run", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("validate", line: 19))
    ep.push_callee(Callee.new("service.save", line: 20))
    ep.push_callee(Callee.new("AuditLog.write", line: 21))
    ep.push_callee(Callee.new("Response.ok", line: 22))
  end,

  Endpoint.new("/hello/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 28))
    ep.push_callee(Callee.new("AuditLog.write", line: 29))
    ep.push_callee(Callee.new("Response.ok", line: 30))
  end,
]

FunctionalTester.new("fixtures/java/dropwizard_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
