require "../../func_spec.cr"

index = Endpoint.new("/posts", "GET").tap do |ep|
  ep.push_callee(Callee.new("PostService::list", line: 11))
  ep.push_callee(Callee.new("PostPresenter::render", line: 12))
  ep.push_callee(Callee.new("Json", line: 13))
end

show = Endpoint.new("/posts/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("PostService::load", line: 17))
  ep.push_callee(Callee.new("AuditLog::read_post", line: 18))
  ep.push_callee(Callee.new("PostPresenter::render", line: 19))
  ep.push_callee(Callee.new("Json", line: 20))
end

create = Endpoint.new("/posts", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("PostService::create", line: 24))
  ep.push_callee(Callee.new("AuditLog::write", line: 25))
  ep.push_callee(Callee.new("PostPresenter::render", line: 26))
  ep.push_callee(Callee.new("Json", line: 27))
end

users = Endpoint.new("/posts/users", "GET", [
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("headers.get", line: 31))
  ep.push_callee(Callee.new("AuthService::validate", line: 32))
  ep.push_callee(Callee.new("Json", line: 33))
  ep.push_callee(Callee.new("UserPresenter::list", line: 33))
end

login = Endpoint.new("/posts/login", "POST", [
  Param.new("form", "", "form"),
]).tap do |ep|
  ep.push_callee(Callee.new("AuthService::login", line: 37))
  ep.push_callee(Callee.new("AuditLog::write", line: 38))
  ep.push_callee(Callee.new("Json", line: 39))
  ep.push_callee(Callee.new("SessionPresenter::render", line: 39))
end

expected_endpoints = [
  index,
  show,
  create,
  users,
  login,
]

FunctionalTester.new("fixtures/rust/loco_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_loco"),
}).perform_tests
