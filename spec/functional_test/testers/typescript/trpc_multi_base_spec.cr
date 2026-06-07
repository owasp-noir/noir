require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/typescript/trpc_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/typescript/trpc_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/a/trpc/user.list", "GET"),
  Endpoint.new("/b/trpc/user.list", "POST"),
]

tester = FunctionalTester.new("fixtures/typescript/trpc_multi_base/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base"       => YAML::Any.new(base_paths),
  "only_techs" => YAML::Any.new("ts_trpc"),
})
tester.perform_tests

it "keeps tRPC routers and prefixes inside each base path" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.url == "/a/trpc/user.list" }
  service_a.method.should eq("GET")

  service_b = tester.app.endpoints.find! { |endpoint| endpoint.url == "/b/trpc/user.list" }
  service_b.method.should eq("POST")
end
