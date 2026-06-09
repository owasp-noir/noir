require "../../func_spec.cr"

hello = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 13))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 14))
  ep.push_callee(Callee.new("render_home", line: 14))
end

get_user = Endpoint.new("/users/{id}", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::load", line: 19))
  ep.push_callee(Callee.new("path.into_inner", line: 19))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 20))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 21))
  ep.push_callee(Callee.new("UserPresenter::render", line: 21))
end

create_user = Endpoint.new("/api/users", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 26))
  ep.push_callee(Callee.new("body.into_inner", line: 26))
  ep.push_callee(Callee.new("AuditLog::write", line: 27))
  ep.push_callee(Callee.new("HttpResponse::Created", line: 28))
  ep.push_callee(Callee.new("UserPresenter::render", line: 28))
end

protected_endpoint = Endpoint.new("/protected", "GET", [
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.headers", line: 37))
  ep.push_callee(Callee.new("AuthService::validate", line: 38))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 39))
end

multi_route_get = Endpoint.new("/multi-a", "GET").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 47))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 48))
end

multi_route_post = Endpoint.new("/multi-b", "POST").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 47))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 48))
end

multi_route_put = Endpoint.new("/multi-c", "PUT").tap do |ep|
  ep.push_callee(Callee.new("MultiService::serve", line: 47))
  ep.push_callee(Callee.new("HttpResponse::Ok", line: 48))
end

external_create = Endpoint.new("/external", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("ExternalService::create", line: 6))
  ep.push_callee(Callee.new("body.into_inner", line: 6))
  ep.push_callee(Callee.new("HttpResponse::Created", line: 7))
end

expected_endpoints = [
  hello,
  get_user,
  create_user,
  protected_endpoint,
  multi_route_get,
  multi_route_post,
  multi_route_put,
  external_create,
]

FunctionalTester.new("fixtures/rust/actix_web_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_actix_web"),
}).perform_tests
