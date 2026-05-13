require "../../func_spec.cr"

users_index = Endpoint.new("/users", "GET").tap do |ep|
  ep.push_callee(Callee.new("UserService.list", line: 5))
  ep.push_callee(Callee.new("users.each", line: 6))
  ep.push_callee(Callee.new("AuditLog.write", line: 6))
  ep.push_callee(Callee.new("json", line: 8))
  ep.push_callee(Callee.new("serialize_users", line: 8))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("JSON.parse", line: 12))
  ep.push_callee(Callee.new("request.body.read", line: 12))
  ep.push_callee(Callee.new("UserService.create", line: 13))
  ep.push_callee(Callee.new("redirect_to", line: 14))
  ep.push_callee(Callee.new("user_url", line: 14))
end

ping = Endpoint.new("/ping", "GET").tap do |ep|
  ep.push_callee(Callee.new("head", line: 17))
end

ready = Endpoint.new("/ready", "GET").tap do |ep|
  ep.push_callee(Callee.new("Health.ready?", line: 20))
  ep.push_callee(Callee.new("Health.check", line: 21))
  ep.push_callee(Callee.new("Health.down", line: 23))
  ep.push_callee(Callee.new("json", line: 25))
  ep.push_callee(Callee.new("status_payload", line: 25))
end

expected_endpoints = [
  users_index,
  users_create,
  ping,
  ready,
]

FunctionalTester.new("fixtures/ruby/sinatra_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
