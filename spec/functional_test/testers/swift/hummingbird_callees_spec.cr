require "../../func_spec.cr"

create_endpoint = Endpoint.new("/users/:id", "POST")
create_endpoint.push_param(Param.new("id", "", "path"))
create_endpoint.push_param(Param.new("body", "", "json"))
create_endpoint.push_callee(Callee.new("context.parameters.require", line: 5))
create_endpoint.push_callee(Callee.new("request.decode", line: 6))
create_endpoint.push_callee(Callee.new("UserService.build", line: 7))
create_endpoint.push_callee(Callee.new("AuditLog.write", line: 8))
create_endpoint.push_callee(Callee.new("user.save", line: 9))

search_endpoint = Endpoint.new("/search", "GET")
search_endpoint.push_param(Param.new("q", "", "query"))
search_endpoint.push_callee(Callee.new("request.uri.queryParameters.get", line: 17))
search_endpoint.push_callee(Callee.new("SearchMetrics.record", line: 18))
search_endpoint.push_callee(Callee.new("SearchService.render", line: 19))

ping_endpoint = Endpoint.new("/ping", "GET")
ping_endpoint.push_callee(Callee.new("PingService.pong", line: 22))

delayed_endpoint = Endpoint.new("/delayed", "GET")
delayed_endpoint.push_callee(Callee.new("DelayService.wait", line: 26))

expected_endpoints = [
  create_endpoint,
  search_endpoint,
  ping_endpoint,
  delayed_endpoint,
]

FunctionalTester.new("fixtures/swift/hummingbird_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
