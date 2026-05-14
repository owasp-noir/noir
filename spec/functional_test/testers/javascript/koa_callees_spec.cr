require "../../func_spec.cr"

# Regression test for --include-callee on Koa. Koa consumes
# JSRouteExtractor, so it can reuse the shared JS callee extractor.
expected_endpoints = [
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
    Param.new("X-Actor", "", "header"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("ctx.get", line: 9))
    ep.push_callee(Callee.new("parseBody", line: 24))
    ep.push_callee(Callee.new("serviceFactory().save", line: 11))
    ep.push_callee(Callee.new("AuditLog.write", line: 12))
    ep.push_callee(Callee.new("serializeUser", line: 32))
  end,

  Endpoint.new("/session", "GET", [
    Param.new("sessionId", "", "cookie"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("ctx.cookies.get", line: 18))
    ep.push_callee(Callee.new("loadProfile", line: 36))
  end,
]

FunctionalTester.new("fixtures/javascript/koa_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
