require "../../func_spec.cr"

show_endpoint = Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")])
show_endpoint.push_callee(Callee.new("UserService.find", line: 15))
show_endpoint.push_callee(Callee.new("params", line: 15))
show_endpoint.push_callee(Callee.new("AuditLog.write", line: 16))
show_endpoint.push_callee(Callee.new("json", line: 17))
show_endpoint.push_callee(Callee.new("serializeUser", line: 17))

create_endpoint = Endpoint.new("/users", "POST", [Param.new("body", "", "json")])
create_endpoint.push_callee(Callee.new("UserPayload.from", line: 24))
create_endpoint.push_callee(Callee.new("UserService.create", line: 25))
create_endpoint.push_callee(Callee.new("json", line: 26))
create_endpoint.push_callee(Callee.new("serializeUser", line: 26))

braces_endpoint = Endpoint.new("/braces", "GET")
braces_endpoint.push_callee(Callee.new("BraceService.render", line: 33))
braces_endpoint.push_callee(Callee.new("json", line: 34))

compact_endpoint = Endpoint.new("/compact", "GET")
compact_endpoint.push_callee(Callee.new("json", line: 37))
compact_endpoint.push_callee(Callee.new("HealthService.check", line: 37))

expected_endpoints = [
  show_endpoint,
  create_endpoint,
  braces_endpoint,
  compact_endpoint,
]

FunctionalTester.new("fixtures/scala/scalatra_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
