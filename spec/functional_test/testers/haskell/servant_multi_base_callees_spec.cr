require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/haskell/servant_multi_base_callees/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/haskell/servant_multi_base_callees/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a", "GET"),
  Endpoint.new("/b", "GET"),
]

tester = FunctionalTester.new("fixtures/haskell/servant_multi_base_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"           => YAML::Any.new(base_paths),
  "only_techs"     => YAML::Any.new("haskell_servant"),
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "keeps Servant handler bodies inside each base path" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.url == "/a" && endpoint.method == "GET" }
  service_a.callees.map(&.name).should contain("serviceA")

  service_b = tester.app.endpoints.find! { |endpoint| endpoint.url == "/b" && endpoint.method == "GET" }
  service_b.callees.map(&.name).should contain("serviceB")
end
