require "../../func_spec.cr"

users_index = Endpoint.new("/users", "GET", [
  Param.new("page", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("request.params", line: 6))
  ep.push_callee(Callee.new("UserService.list", line: 7))
  ep.push_callee(Callee.new("AuditLog.write", line: 8))
  ep.push_callee(Callee.new("response.render", line: 9))
  ep.push_callee(Callee.new("serialize_users", line: 9))
end

users_create = Endpoint.new("/users", "POST", [
  Param.new("name", "", "json"),
  Param.new("email", "", "json"),
  Param.new("source", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("BuildUser.call", line: 11))
  ep.push_callee(Callee.new("request.params", line: 11))
  ep.push_callee(Callee.new("UserService.create", line: 12))
  ep.push_callee(Callee.new("response.render", line: 13))
  ep.push_callee(Callee.new("serialize_user", line: 13))
end

users_show = Endpoint.new("/users/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("Feature.enabled?", line: 6))
  ep.push_callee(Callee.new("UserService.find", line: 7))
  ep.push_callee(Callee.new("UserFallback.find", line: 9))
  ep.push_callee(Callee.new("response.render", line: 11))
  ep.push_callee(Callee.new("serialize_user", line: 11))
end

users_destroy = Endpoint.new("/users/:id", "DELETE", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService.delete", line: 5))
  ep.push_callee(Callee.new("response.status", line: 5))
end

health_ready = Endpoint.new("/ready", "GET").tap do |ep|
  ep.push_callee(Callee.new("response.render", line: 5))
  ep.push_callee(Callee.new("HealthCheck.ready", line: 5))
end

missing_action = Endpoint.new("/missing", "GET")

expected_endpoints = [
  users_index,
  users_create,
  users_show,
  users_destroy,
  health_ready,
  missing_action,
]

FunctionalTester.new("fixtures/ruby/hanami_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
