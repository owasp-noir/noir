require "../../func_spec.cr"

# Regression test for --include-callee on Restify. Restify consumes
# JSRouteExtractor, so direct parser-covered routes reuse the shared
# JS callee extractor. Prefix semantics in applyRoutes(base) stay out
# of scope for this fixture.
expected_endpoints = [
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
    Param.new("X-Actor", "", "header"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("req.header", line: 9))
    ep.push_callee(Callee.new("parseUser", line: 34))
    ep.push_callee(Callee.new("serviceFactory().save", line: 11))
    ep.push_callee(Callee.new("AuditLog.write", line: 12))
    ep.push_callee(Callee.new("res.send", line: 14))
    ep.push_callee(Callee.new("serializeUser", line: 42))
  end,

  Endpoint.new("/health", "GET").tap do |ep|
    ep.push_callee(Callee.new("loadHealth", line: 46))
    ep.push_callee(Callee.new("res.send", line: 21))
  end,

  Endpoint.new("/profile", "GET", [
    Param.new("userId", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("loadProfile", line: 50))
    ep.push_callee(Callee.new("res.send", line: 30))
  end,
]

FunctionalTester.new("fixtures/javascript/restify_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
