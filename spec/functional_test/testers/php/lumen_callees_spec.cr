require "../../func_spec.cr"

health = Endpoint.new("/health", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 4))
  ep.push_callee(Callee.new("response", line: 5))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("BuildUser::fromRequest", line: 9))
  ep.push_callee(Callee.new("UserService::create", line: 10))
  ep.push_callee(Callee.new("response", line: 11))
end

contact_callees = [
  Callee.new("ContactNotifier::deliver", line: 15),
  Callee.new("view", line: 16),
]

contact_get = Endpoint.new("/contact", "GET").tap do |ep|
  contact_callees.each { |callee| ep.push_callee(callee) }
end

contact_post = Endpoint.new("/contact", "POST").tap do |ep|
  contact_callees.each { |callee| ep.push_callee(callee) }
end

ready = Endpoint.new("/api/v1/ready", "GET").tap do |ep|
  ep.push_callee(Callee.new("ReadyProbe::check", line: 21))
end

reports = Endpoint.new("/reports", "GET")

expected_endpoints = [
  health,
  users_create,
  contact_get,
  contact_post,
  ready,
  reports,
]

tester = FunctionalTester.new("fixtures/php/lumen_callees/", {
  :techs     => 1,
  :endpoints => 6,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("php_lumen"),
})
tester.perform_tests

describe "Lumen callee extraction" do
  it "leaves controller string handlers callee-empty until ImportGraph resolves them" do
    reports_endpoint = tester.app.endpoints.find { |e| e.method == "GET" && e.url == "/reports" }
    reports_endpoint.should_not be_nil
    reports_endpoint.callees.should be_empty if reports_endpoint
  end
end
