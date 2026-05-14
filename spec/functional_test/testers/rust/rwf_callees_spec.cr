require "../../func_spec.cr"

users_get = Endpoint.new("/users", "GET").tap do |ep|
  ep.push_callee(Callee.new("UserService::list", line: 12))
  ep.push_callee(Callee.new("AuditLog::list_users", line: 13))
  ep.push_callee(Callee.new("Response::new", line: 14))
  ep.push_callee(Callee.new("UserPresenter::render", line: 14))
end

users_post = Endpoint.new("/users", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("request.body", line: 17))
  ep.push_callee(Callee.new("UserService::create", line: 18))
  ep.push_callee(Callee.new("AuditLog::write", line: 19))
end

user_show = Endpoint.new("/users/:id", "GET", [
  Param.new("id", "", "path"),
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("request.path_parameter", line: 33))
  ep.push_callee(Callee.new("request.header", line: 34))
  ep.push_callee(Callee.new("UserService::load", line: 35))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 36))
  ep.push_callee(Callee.new("UserPresenter::render", line: 37))
end

session = Endpoint.new("/session", "GET", [
  Param.new("redirect", "", "query"),
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("request.cookie", line: 47))
  ep.push_callee(Callee.new("request.query_parameter", line: 48))
  ep.push_callee(Callee.new("AuthService::session", line: 49))
  ep.push_callee(Callee.new("Response::new", line: 50))
end

expected_endpoints = [
  users_get,
  users_post,
  user_show,
  session,
]

FunctionalTester.new("fixtures/rust/rwf_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_rwf"),
}).perform_tests
