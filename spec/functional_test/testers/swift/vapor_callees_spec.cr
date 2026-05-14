require "../../func_spec.cr"

create_endpoint = Endpoint.new("/users/:id", "POST")
create_endpoint.push_param(Param.new("id", "", "path"))
create_endpoint.push_param(Param.new("body", "", "json"))
create_endpoint.push_callee(Callee.new("req.parameters.get", line: 5))
create_endpoint.push_callee(Callee.new("req.content.decode", line: 6))
create_endpoint.push_callee(Callee.new("UserService.build", line: 7))
create_endpoint.push_callee(Callee.new("AuditLog.write", line: 8))
create_endpoint.push_callee(Callee.new("user.save", line: 9))
create_endpoint.push_callee(Callee.new("ResponseBuilder.created", line: 10))

health_endpoint = Endpoint.new("/health", "GET")
health_endpoint.push_callee(Callee.new("HealthService.check", line: 19))

ping_endpoint = Endpoint.new("/ping", "GET")
ping_endpoint.push_callee(Callee.new("PingService.pong", line: 23))

expected_endpoints = [
  create_endpoint,
  health_endpoint,
  ping_endpoint,
]

FunctionalTester.new("fixtures/swift/vapor_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
