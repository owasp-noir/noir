require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 20))
  ep.push_callee(Callee.new("Html", line: 21))
  ep.push_callee(Callee.new("render_home", line: 21))
end

profile = Endpoint.new("/profile", "GET").tap do |ep|
  ep.push_callee(Callee.new("ProfileService::load", line: 25))
  ep.push_callee(Callee.new("FeatureFlags::enabled", line: 26))
  ep.push_callee(Callee.new("Metrics::record_profile", line: 27))
  ep.push_callee(Callee.new("Json", line: 29))
  ep.push_callee(Callee.new("ProfilePresenter::render", line: 29))
end

create_user = Endpoint.new("/users", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 33))
  ep.push_callee(Callee.new("AuditLog::write", line: 34))
  ep.push_callee(Callee.new("Json", line: 35))
end

create_external = Endpoint.new("/external", "POST", [
  Param.new("body", "", "json"),
]).tap do |ep|
  ep.push_callee(Callee.new("ExternalService::create", line: 4))
  ep.push_callee(Callee.new("Json", line: 5))
end

read_account = Endpoint.new("/account", "GET").tap do |ep|
  ep.push_callee(Callee.new("AccountService::read", line: 51))
  ep.push_callee(Callee.new("Json", line: 52))
end

update_account = Endpoint.new("/account", "PUT").tap do |ep|
  ep.push_callee(Callee.new("AccountService::update", line: 57))
  ep.push_callee(Callee.new("AuditLog::write_update", line: 58))
end

builder_get = Endpoint.new("/builder", "GET").tap do |ep|
  ep.push_callee(Callee.new("BuilderService::read", line: 63))
end

builder_public = Endpoint.new("/builder-public", "POST").tap do |ep|
  ep.push_callee(Callee.new("BuilderService::create", line: 67))
end

scoped = Endpoint.new("/scoped", "GET").tap do |ep|
  ep.push_callee(Callee.new("RightService::hit", line: 88))
end

expected_endpoints = [
  home,
  profile,
  create_user,
  create_external,
  read_account,
  update_account,
  builder_get,
  builder_public,
  scoped,
]

FunctionalTester.new("fixtures/rust/axum_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_axum"),
}).perform_tests
