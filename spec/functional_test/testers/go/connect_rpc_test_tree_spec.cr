require "../../func_spec.cr"

# A proto under testdata/, src/test/ or fixtures/ is test input, not a service
# this project serves. The gRPC analyzer already drops it; go_connect_rpc used
# to read the same locator key directly and kept all three.
expected_endpoints = [
  Endpoint.new("/greet.v1.GreetService/Greet", "POST", [
    Param.new("name", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/go/connect_rpc_test_tree/", {
  :techs     => 3,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
