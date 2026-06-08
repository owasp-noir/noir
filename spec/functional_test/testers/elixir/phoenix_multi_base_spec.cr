require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/elixir/phoenix_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/elixir/phoenix_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/service-a/shared", "GET", [
    Param.new("a", "", "query"),
  ]),
  Endpoint.new("/service-b/shared", "GET", [
    Param.new("b", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/elixir/phoenix_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("elixir_phoenix"),
})

tester.perform_tests

it "keeps Phoenix controller params scoped to each configured base" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/service-a/shared" }
  service_b = tester.app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/service-b/shared" }

  service_a_params = service_a.params.select { |param| param.param_type == "query" }.map(&.name).sort!
  service_b_params = service_b.params.select { |param| param.param_type == "query" }.map(&.name).sort!

  service_a_params.should eq ["a"]
  service_b_params.should eq ["b"]
end
