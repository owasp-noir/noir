require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/perl/catalyst_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/perl/catalyst_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/:root_capture/item", "GET", [
    Param.new("root_capture", "", "path"),
  ]),
  Endpoint.new("/b/:root_capture/item", "GET", [
    Param.new("root_capture", "", "path"),
  ]),
]

tester = FunctionalTester.new("fixtures/perl/catalyst_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("perl_catalyst"),
})
tester.perform_tests

it "keeps Catalyst chained actions inside each base path" do
  tester.app.endpoints.any? { |endpoint| endpoint.url == "/a/:root_capture/item" }.should be_true
  tester.app.endpoints.any? { |endpoint| endpoint.url == "/b/:root_capture/item" }.should be_true
end
