require "../../func_spec.cr"

def mojolicious_multi_base_endpoint(url, method, callees = [] of Callee)
  endpoint = Endpoint.new(url, method)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/perl/mojolicious_callees_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/perl/mojolicious_callees_multi_base/service_b"),
]

service_a_controller = "./spec/functional_test/fixtures/perl/mojolicious_callees_multi_base/service_a/lib/MyApp/Controller/Api.pm"
service_b_controller = "./spec/functional_test/fixtures/perl/mojolicious_callees_multi_base/service_b/lib/MyApp/Controller/Api.pm"

expected_endpoints = [
  mojolicious_multi_base_endpoint("/a/status", "GET", [
    Callee.new("AService.call", path: service_a_controller, line: 5),
    Callee.new("c.render", path: service_a_controller, line: 6),
  ]),
  mojolicious_multi_base_endpoint("/b/status", "GET", [
    Callee.new("BService.call", path: service_b_controller, line: 5),
    Callee.new("c.render", path: service_b_controller, line: 6),
  ]),
]

tester = FunctionalTester.new("fixtures/perl/mojolicious_callees_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"           => YAML::Any.new(base_paths),
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("perl_mojolicious"),
})
tester.perform_tests

it "keeps Mojolicious controller callees inside each base path" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.url == "/a/status" && endpoint.method == "GET" }
  service_a.callees.map(&.name).should contain("AService.call")
  service_a.callees.map(&.name).should_not contain("BService.call")

  service_b = tester.app.endpoints.find! { |endpoint| endpoint.url == "/b/status" && endpoint.method == "GET" }
  service_b.callees.map(&.name).should contain("BService.call")
  service_b.callees.map(&.name).should_not contain("AService.call")
end
