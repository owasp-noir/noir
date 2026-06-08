require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/dart/serverpod_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/dart/serverpod_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a-web", "GET"),
  Endpoint.new("/b-web", "POST"),
]

tester = FunctionalTester.new("fixtures/dart/serverpod_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("dart_serverpod"),
})
tester.perform_tests

it "keeps Serverpod web route classes inside each base path" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.url == "/a-web" }
  service_a.method.should eq("GET")

  service_b = tester.app.endpoints.find! { |endpoint| endpoint.url == "/b-web" }
  service_b.method.should eq("POST")
end
