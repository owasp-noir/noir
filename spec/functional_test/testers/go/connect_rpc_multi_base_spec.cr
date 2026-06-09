require "../../func_spec.cr"

base_paths = [
  YAML::Any.new("./spec/functional_test/fixtures/go/connect_rpc_multi_base/service_a"),
  YAML::Any.new("./spec/functional_test/fixtures/go/connect_rpc_multi_base/service_b"),
]

expected_endpoints = [
  Endpoint.new("/servicea.v1.UserService/Get", "POST", [
    Param.new("user_id", "", "json"),
  ]),
  Endpoint.new("/serviceb.v1.UserService/Get", "POST", [
    Param.new("user_id", "", "json"),
  ]),
]

tester = FunctionalTester.new("fixtures/go/connect_rpc_multi_base/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "base" => YAML::Any.new(base_paths),
})
tester.perform_tests

it "keeps Connect RPC service mounts inside each base path" do
  service_a = tester.app.endpoints.find! { |endpoint| endpoint.url == "/servicea.v1.UserService/Get" }
  service_b = tester.app.endpoints.find! { |endpoint| endpoint.url == "/serviceb.v1.UserService/Get" }

  service_a.details.code_paths.first.path.should contain("/service_a/")
  service_b.details.code_paths.first.path.should contain("/service_b/")
end
