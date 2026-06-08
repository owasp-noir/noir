require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/python/pyramid_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/python/pyramid_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-home", "GET", [
    Param.new("a", "", "query"),
  ]),
  Endpoint.new("/b-home", "GET", [
    Param.new("b", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/python/pyramid_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("python_pyramid"),
})
tester.perform_tests

it "keeps Pyramid route names inside each base path" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/a-home" }
  service_a.params.map(&.name).sort!.should eq(["a"])

  service_b = tester.app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/b-home" }
  service_b.params.map(&.name).sort!.should eq(["b"])
end
