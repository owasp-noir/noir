require "../../func_spec.cr"

# Regression test for --include-callee on Fastify. Fastify consumes
# JSRouteExtractor, so it can reuse the shared JS callee extractor
# introduced for Hono.
expected_endpoints = [
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("parseUser", line: 20))
    ep.push_callee(Callee.new("serviceFactory().save", line: 8))
    ep.push_callee(Callee.new("AuditLog.write", line: 9))
    ep.push_callee(Callee.new("reply.send", line: 11))
  end,

  Endpoint.new("/profile", "GET", [
    Param.new("userId", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("loadProfile", line: 28))
    ep.push_callee(Callee.new("reply.send", line: 17))
  end,
]

FunctionalTester.new("fixtures/javascript/fastify_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
