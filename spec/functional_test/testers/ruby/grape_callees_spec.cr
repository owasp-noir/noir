require "../../func_spec.cr"

users_index = Endpoint.new("/api/users", "GET").tap do |ep|
  ep.push_callee(Callee.new("UserService.list", line: 12))
  ep.push_callee(Callee.new("AuditLog.write", line: 13))
  ep.push_callee(Callee.new("present", line: 14))
  ep.push_callee(Callee.new("serialize_users", line: 14))
end

users_create = Endpoint.new("/api/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("BuildUser.call", line: 22))
  ep.push_callee(Callee.new("UserService.create", line: 23))
  ep.push_callee(Callee.new("present", line: 24))
  ep.push_callee(Callee.new("serialize_user", line: 24))
end

users_show = Endpoint.new("/api/users/{id}", "GET").tap do |ep|
  ep.push_callee(Callee.new("Feature.enabled?", line: 28))
  ep.push_callee(Callee.new("UserService.find", line: 29))
  ep.push_callee(Callee.new("UserFallback.find", line: 31))
  ep.push_callee(Callee.new("present", line: 33))
  ep.push_callee(Callee.new("serialize_user", line: 33))
end

users_delete = Endpoint.new("/api/users/{id}", "DELETE").tap do |ep|
  ep.push_callee(Callee.new("UserService.delete", line: 36))
end

expected_endpoints = [
  users_index,
  users_create,
  users_show,
  users_delete,
]

FunctionalTester.new("fixtures/ruby/grape_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
