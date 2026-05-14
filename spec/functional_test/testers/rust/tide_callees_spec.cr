require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 33))
  ep.push_callee(Callee.new("render_home", line: 34))
end

get_user = Endpoint.new("/users/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.param", line: 38))
  ep.push_callee(Callee.new("UserService::load", line: 39))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 40))
  ep.push_callee(Callee.new("UserPresenter::render", line: 41))
end

create_user = Endpoint.new("/api/users", "POST", [
  Param.new("UserData", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.body_json", line: 45))
  ep.push_callee(Callee.new("UserService::create", line: 46))
  ep.push_callee(Callee.new("UserPresenter::render", line: 47))
end

update_account = Endpoint.new("/accounts/:id", "PUT", [
  Param.new("id", "", "path"),
  Param.new("SearchQuery", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.query", line: 51))
  ep.push_callee(Callee.new("AccountService::update", line: 52))
  ep.push_callee(Callee.new("AccountPresenter::render", line: 53))
end

auth_handler = Endpoint.new("/auth", "GET", [
  Param.new("Authorization", "", "header"),
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.header", line: 57))
  ep.push_callee(Callee.new("req.cookie", line: 58))
  ep.push_callee(Callee.new("AuthService::validate", line: 59))
end

complex_handler = Endpoint.new("/complex/:id", "POST", [
  Param.new("id", "", "path"),
  Param.new("SearchQuery", "", "query"),
  Param.new("UserData", "", "json"),
  Param.new("Authorization", "", "header"),
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("req.param", line: 64))
  ep.push_callee(Callee.new("req.query", line: 65))
  ep.push_callee(Callee.new("req.body_json", line: 66))
  ep.push_callee(Callee.new("req.header", line: 67))
  ep.push_callee(Callee.new("req.cookie", line: 68))
  ep.push_callee(Callee.new("ComplexService::process", line: 69))
end

expected_endpoints = [
  home,
  get_user,
  create_user,
  update_account,
  auth_handler,
  complex_handler,
]

FunctionalTester.new("fixtures/rust/tide_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_tide"),
}).perform_tests
