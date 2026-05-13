require "../../func_spec.cr"

hello = Endpoint.new("/hello", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 7))
  ep.push_callee(Callee.new("render_home", line: 8))
end

get_user = Endpoint.new("/users/{id}", "GET", [
  Param.new("id", "", "path"),
  Param.new("X-Token", "", "header"),
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.header", line: 13))
  ep.push_callee(Callee.new("req.cookie", line: 14))
  ep.push_callee(Callee.new("UserService::load", line: 15))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 16))
  ep.push_callee(Callee.new("UserPresenter::render", line: 17))
end

create_user = Endpoint.new("/users", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 22))
  ep.push_callee(Callee.new("UserPresenter::render", line: 23))
end

create_item = Endpoint.new("/api/items/{id}", "POST", [
  Param.new("id", "", "path"),
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("ItemService::create", line: 9))
  ep.push_callee(Callee.new("AuditLog::write", line: 10))
  ep.push_callee(Callee.new("ItemPresenter::render", line: 11))
  ep.push_callee(Callee.new("Json", line: 12))
end

expected_endpoints = [
  hello,
  get_user,
  create_user,
  create_item,
]

FunctionalTester.new("fixtures/rust/poem_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_poem"),
}).perform_tests
