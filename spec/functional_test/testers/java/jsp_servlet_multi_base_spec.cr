require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/java/jsp_servlet_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/java/jsp_servlet_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-servlet", "GET", [Param.new("a", "", "query")]),
  Endpoint.new("/b-servlet", "GET", [Param.new("b", "", "query")]),
]

tester = FunctionalTester.new("fixtures/java/jsp_servlet_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("java_jsp"),
})

tester.perform_tests

describe "JSP servlet multi-base scoping" do
  it "keeps servlet params inside the web.xml base path" do
    service_a = tester.app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/a-servlet" }
    service_a.params.map(&.name).sort!.should eq(["a"])

    service_b = tester.app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/b-servlet" }
    service_b.params.map(&.name).sort!.should eq(["b"])
  end
end
