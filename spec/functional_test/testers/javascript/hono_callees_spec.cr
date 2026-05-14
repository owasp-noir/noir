require "../../func_spec.cr"

# Regression test for --include-callee on Hono. The shared JS callee
# extractor is enabled through JSRouteExtractor and the Hono adapter
# consumes those parser endpoints directly.
expected_endpoints = [
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("c.req.param", line: 8))
    ep.push_callee(Callee.new("parseUser", line: 29))
    ep.push_callee(Callee.new("serviceFactory().save", line: 10))
    ep.push_callee(Callee.new("AuditLog.write", line: 11))
    ep.push_callee(Callee.new("c.json", line: 13))
  end,

  Endpoint.new("/profile", "GET", [
    Param.new("sessionId", "", "cookie"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("getCookie", line: 17))
    ep.push_callee(Callee.new("buildProfile", line: 37))
    ep.push_callee(Callee.new("c.json", line: 20))
  end,

  Endpoint.new("/health", "GET").tap do |ep|
    ep.push_callee(Callee.new("healthService.check", line: 24))
    ep.push_callee(Callee.new("c.json", line: 26))
  end,
]

FunctionalTester.new("fixtures/javascript/hono_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
