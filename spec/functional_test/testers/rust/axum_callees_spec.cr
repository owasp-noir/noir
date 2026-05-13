require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 17))
  ep.push_callee(Callee.new("Html", line: 18))
  ep.push_callee(Callee.new("render_home", line: 18))
end

profile = Endpoint.new("/profile", "GET").tap do |ep|
  ep.push_callee(Callee.new("ProfileService::load", line: 22))
  ep.push_callee(Callee.new("FeatureFlags::enabled", line: 23))
  ep.push_callee(Callee.new("Metrics::record_profile", line: 24))
  ep.push_callee(Callee.new("Json", line: 26))
  ep.push_callee(Callee.new("ProfilePresenter::render", line: 26))
end

create_user = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("UserService::create", line: 30))
  ep.push_callee(Callee.new("AuditLog::write", line: 31))
  ep.push_callee(Callee.new("Json", line: 32))
end

expected_endpoints = [
  home,
  profile,
  create_user,
]

FunctionalTester.new("fixtures/rust/axum_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("rust_axum"),
}).perform_tests
