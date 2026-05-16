require "../../func_spec.cr"

# Regression test for --include-callee on Micronaut. The extractor
# fans out `uris = {...}` into multiple endpoints, and each emitted
# endpoint should receive the same method-body callees.
highlight_callees = [
  Callee.new("this.buildProfile", line: 25),
  Callee.new("AuditLog.write", line: 26),
  Callee.new("HttpResponse.ok", line: 27),
]

expected_endpoints = [
  Endpoint.new("/books/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("dry_run", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("validate", line: 17))
    ep.push_callee(Callee.new("service.save", line: 18))
    ep.push_callee(Callee.new("AuditLog.write", line: 19))
    ep.push_callee(Callee.new("HttpResponse.ok", line: 20))
  end,

  Endpoint.new("/books/popular", "GET").tap do |ep|
    highlight_callees.each { |callee| ep.push_callee(callee) }
  end,

  Endpoint.new("/books/featured", "GET").tap do |ep|
    highlight_callees.each { |callee| ep.push_callee(callee) }
  end,
]

FunctionalTester.new("fixtures/java/micronaut_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
