require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/csharp/fastendpoints_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/csharp/fastendpoints_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/users", "POST", [
    Param.new("Name", "", "json"),
  ]),
  Endpoint.new("/b/users", "POST", [
    Param.new("Email", "", "json"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/fastendpoints_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("cs_fastendpoints"),
})

tester.perform_tests

describe "FastEndpoints multi-base DTO scoping" do
  it "keeps request DTO params inside the endpoint's base path" do
    service_a = tester.app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/a/users" }
    service_a.params.map(&.name).sort!.should eq(["Name"])

    service_b = tester.app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/b/users" }
    service_b.params.map(&.name).sort!.should eq(["Email"])
  end
end
