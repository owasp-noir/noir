require "../../func_spec.cr"

index = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 17))
  ep.push_callee(Callee.new("render_home", line: 18))
end

get_user = Endpoint.new("/users/{id}", "GET", [
  Param.new("id", "", "path"),
  Param.new("verbose", "", "query"),
  Param.new("x-trace-id", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("request.headers", line: 23))
  ep.push_callee(Callee.new("UserService::load", line: 24))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 25))
  ep.push_callee(Callee.new("UserPresenter::render", line: 26))
end

create_user = Endpoint.new("/api/users", "POST", [
  Param.new("user", "", "body"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 31))
  ep.push_callee(Callee.new("user.into_inner", line: 31))
  ep.push_callee(Callee.new("AuditLog::write", line: 32))
  ep.push_callee(Callee.new("UserPresenter::render", line: 33))
end

session = Endpoint.new("/session", "GET", [
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("cookies.get", line: 40))
  ep.push_callee(Callee.new("AuthService::session", line: 41))
end

multi_route_get = Endpoint.new("/multi-a", "GET").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 48))
end

multi_route_post = Endpoint.new("/multi-b", "POST").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 48))
end

multi_route_put = Endpoint.new("/multi-c", "PUT").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 48))
end

expected_endpoints = [
  index,
  get_user,
  create_user,
  session,
  multi_route_get,
  multi_route_post,
  multi_route_put,
]

FunctionalTester.new("fixtures/rust/rocket_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_rocket"),
}).perform_tests
