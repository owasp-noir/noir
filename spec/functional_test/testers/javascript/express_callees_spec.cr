require "../../func_spec.cr"

# Regression test for --include-callee on Express. Express consumes
# JSRouteExtractor after its router-mount pre-scan, so parser-covered
# handlers can reuse the shared JS callee extractor.
#
# Bare identifier callees that match a same-file top-level function or
# const-arrow declaration are resolved to the declaration line; member
# expressions and unknown identifiers stay at the call site.
expected_endpoints = [
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
    Param.new("include", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("parseUser", line: 25))
    ep.push_callee(Callee.new("serviceFactory().save", line: 10))
    ep.push_callee(Callee.new("AuditLog.write", line: 11))
    ep.push_callee(Callee.new("res.json", line: 13))
    ep.push_callee(Callee.new("serializeUser", line: 33))
  end,

  Endpoint.new("/api/profile", "GET", [
    Param.new("sessionId", "", "cookie"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("loadProfile", line: 37))
    ep.push_callee(Callee.new("res.send", line: 20))
  end,
]

FunctionalTester.new("fixtures/javascript/express_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
