require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 15))
  ep.push_callee(Callee.new("render_home", line: 16))
end

get_user = Endpoint.new("/users/:param", "GET", [
  Param.new("param", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::load", line: 20))
  ep.push_callee(Callee.new("AuditLog::read_user", line: 21))
  ep.push_callee(Callee.new("UserPresenter::render", line: 22))
end

create_user = Endpoint.new("/users", "POST", [
  Param.new("CreateUser", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 26))
  ep.push_callee(Callee.new("AuditLog::write", line: 27))
  ep.push_callee(Callee.new("UserPresenter::render", line: 28))
end

external = Endpoint.new("/external", "POST", [
  Param.new("CreateUser", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("ExternalService::create", line: 2))
  ep.push_callee(Callee.new("AuditLog::write_external", line: 3))
  ep.push_callee(Callee.new("UserPresenter::render", line: 4))
end

profile = Endpoint.new("/profile", "GET", [
  Param.new("SearchQuery", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("ProfileService::search", line: 32))
  ep.push_callee(Callee.new("ProfilePresenter::render", line: 33))
end

generic = Endpoint.new("/generic", "GET").tap do |ep|
  ep.push_callee(Callee.new("GenericService::load", line: 37))
  ep.push_callee(Callee.new("GenericPresenter::render", line: 38))
end

expected_endpoints = [
  home,
  get_user,
  create_user,
  external,
  profile,
  generic,
]

FunctionalTester.new("fixtures/rust/warp_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_warp"),
}).perform_tests
