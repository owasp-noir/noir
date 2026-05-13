require "../../func_spec.cr"

hello = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 11))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 12))
  ep.push_callee(Callee.new("render_home", line: 12))
end

get_user = Endpoint.new("/users/{id}", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::load", line: 17))
  ep.push_callee(Callee.new("path.into_inner", line: 17))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 18))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 19))
  ep.push_callee(Callee.new("UserPresenter::render", line: 19))
end

create_user = Endpoint.new("/api/users", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 24))
  ep.push_callee(Callee.new("body.into_inner", line: 24))
  ep.push_callee(Callee.new("AuditLog::write", line: 25))
  ep.push_callee(Callee.new("HttpResponse::Created", line: 26))
  ep.push_callee(Callee.new("UserPresenter::render", line: 26))
end

protected_endpoint = Endpoint.new("/protected", "GET", [
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.headers", line: 35))
  ep.push_callee(Callee.new("AuthService::validate", line: 36))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 37))
end

multi_route_get = Endpoint.new("/multi-a", "GET").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 45))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 46))
end

multi_route_post = Endpoint.new("/multi-b", "POST").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 45))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 46))
end

multi_route_put = Endpoint.new("/multi-c", "PUT").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 45))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 46))
end

expected_endpoints = [
  hello,
  get_user,
  create_user,
  protected_endpoint,
  multi_route_get,
  multi_route_post,
  multi_route_put,
]

FunctionalTester.new("fixtures/rust/actix_web_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_actix_web"),
}).perform_tests
