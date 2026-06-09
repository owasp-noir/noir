require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/dart/shelf_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/dart/shelf_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/shared", "GET"),
  Endpoint.new("/b/shared", "POST"),
]

tester = FunctionalTester.new("fixtures/dart/shelf_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("dart_shelf"),
})
tester.perform_tests

it "keeps Shelf router mounts inside each base path" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.url == "/a/shared" }
  service_a.method.should eq("GET")

  service_b = tester.app.endpoints.find! { |endpoint| endpoint.url == "/b/shared" }
  service_b.method.should eq("POST")
end
