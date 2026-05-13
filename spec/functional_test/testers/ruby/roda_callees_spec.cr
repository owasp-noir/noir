require "../../func_spec.cr"

root = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.index", line: 6))
  ep.push_callee(Callee.new("json", line: 7))
  ep.push_callee(Callee.new("serialize_home", line: 7))
end

users_index = Endpoint.new("/users", "GET").tap do |ep|
  ep.push_callee(Callee.new("r.params", line: 12))
  ep.push_callee(Callee.new("UserService.list", line: 13))
  ep.push_callee(Callee.new("response.write", line: 14))
  ep.push_callee(Callee.new("serialize_users", line: 14))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("UserService.create", line: 17))
  ep.push_callee(Callee.new("JSON.parse", line: 17))
  ep.push_callee(Callee.new("r.body.read", line: 17))
end

users_show = Endpoint.new("/users/{id}", "GET").tap do |ep|
  ep.push_callee(Callee.new("Feature.enabled?", line: 21))
  ep.push_callee(Callee.new("UserService.find", line: 22))
  ep.push_callee(Callee.new("UserFallback.find", line: 24))
  ep.push_callee(Callee.new("response.write", line: 26))
  ep.push_callee(Callee.new("serialize_user", line: 26))
end

users_delete = Endpoint.new("/users/{id}", "DELETE").tap do |ep|
  ep.push_callee(Callee.new("UserService.delete", line: 30))
  ep.push_callee(Callee.new("response.status", line: 31))
end

users_toggle = Endpoint.new("/users/{id}/toggle", "PATCH").tap do |ep|
  ep.push_callee(Callee.new("Feature.enabled?", line: 35))
  ep.push_callee(Callee.new("UserService.enable", line: 35))
  ep.push_callee(Callee.new("UserService.disable", line: 35))
  ep.push_callee(Callee.new("response.write", line: 36))
  ep.push_callee(Callee.new("serialize_state", line: 36))
end

users_options = Endpoint.new("/users/{id}", "OPTIONS").tap do |ep|
  ep.push_callee(Callee.new("OptionsService.allow", line: 39))
end

expected_endpoints = [
  root,
  users_index,
  users_create,
  users_show,
  users_delete,
  users_toggle,
  users_options,
]

FunctionalTester.new("fixtures/ruby/roda_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
