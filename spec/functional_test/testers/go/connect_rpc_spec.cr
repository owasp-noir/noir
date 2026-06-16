require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/user.v1.UserService/GetUser", "POST", [
    Param.new("user_id", "", "json"),
  ]),
  Endpoint.new("/user.v1.UserService/CreateUser", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "", "json"),
  ]),
  Endpoint.new("/user.v1.UserService/ListUsers", "POST", [
    Param.new("page", "", "json"),
    Param.new("page_size", "", "json"),
  ]),
  Endpoint.new("/user.v1.UserService/StreamUsers", "POST", [
    Param.new("page", "", "json"),
    Param.new("page_size", "", "json"),
  ]),
]

# The .proto file in the fixture also fires the gRPC spec detector, so
# both `grpc` and `go_connect_rpc` techs are expected. The main server
# also uses bare net/http (http.NewServeMux) so `go_http` is detected too
# (legitimate). After endpoint optimization the pure-GRPC paths are
# deduplicated, leaving exactly the expected endpoints.
FunctionalTester.new("fixtures/go/connect_rpc/", {
  :techs     => 3,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
