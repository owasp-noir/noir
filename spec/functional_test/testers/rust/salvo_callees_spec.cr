require "../../func_spec.cr"

hello = Endpoint.new("/hello", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 5))
  ep.push_callee(Callee.new("render_home", line: 6))
end

get_user = Endpoint.new("/users/<id>", "GET", [
  Param.new("id", "", "path"),
  Param.new("X-Token", "", "header"),
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.header", line: 11))
  ep.push_callee(Callee.new("req.cookie", line: 12))
  ep.push_callee(Callee.new("UserService::load", line: 13))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 14))
  ep.push_callee(Callee.new("UserPresenter::render", line: 15))
end

create_user = Endpoint.new("/users", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.extract", line: 20))
  ep.push_callee(Callee.new("UserService::create", line: 21))
  ep.push_callee(Callee.new("UserPresenter::render", line: 22))
end

submit_form = Endpoint.new("/api/submit/<id>", "POST", [
  Param.new("id", "", "path"),
  Param.new("form", "", "form"),
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.extract", line: 28))
  ep.push_callee(Callee.new("req.header", line: 29))
  ep.push_callee(Callee.new("SubmitService::save", line: 30))
end

expected_endpoints = [
  hello,
  get_user,
  create_user,
  submit_form,
]

FunctionalTester.new("fixtures/rust/salvo_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_salvo"),
}).perform_tests
