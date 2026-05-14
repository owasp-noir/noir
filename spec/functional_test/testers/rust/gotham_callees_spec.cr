require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 7))
  ep.push_callee(Callee.new("render_home", line: 8))
  ep.push_callee(Callee.new("respond", line: 9))
end

user = Endpoint.new("/users/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::load", line: 13))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 14))
  ep.push_callee(Callee.new("UserPresenter::render", line: 15))
  ep.push_callee(Callee.new("respond", line: 16))
end

create_user = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 20))
  ep.push_callee(Callee.new("AuditLog::write", line: 21))
  ep.push_callee(Callee.new("UserPresenter::render", line: 22))
  ep.push_callee(Callee.new("respond", line: 23))
end

session = Endpoint.new("/session", "GET", [
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("state.cookie", line: 27))
  ep.push_callee(Callee.new("AuthService::session", line: 28))
  ep.push_callee(Callee.new("respond", line: 29))
end

auth = Endpoint.new("/auth", "GET", [
  Param.new("Authorization", "", "header"),
  Param.new("X-API-Key", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("state.headers", line: 33))
  ep.push_callee(Callee.new("AuthService::validate", line: 35))
  ep.push_callee(Callee.new("respond", line: 36))
end

expected_endpoints = [
  home,
  user,
  create_user,
  session,
  auth,
]

FunctionalTester.new("fixtures/rust/gotham_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_gotham"),
}).perform_tests
