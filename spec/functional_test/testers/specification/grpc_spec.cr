require "../../func_spec.cr"

expected_endpoints = [
  # Pure gRPC endpoint
  Endpoint.new("/example.v1.UserService/ListUsers", "POST", [
    Param.new("page", "", "json"),
    Param.new("page_size", "", "json"),
  ]),
  # gRPC-Gateway endpoints
  Endpoint.new("/api/v1/users/{user_id}", "GET", [
    Param.new("user_id", "", "path"),
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/api/v1/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("age", "", "json"),
  ]),
  Endpoint.new("/api/v1/users/{user_id}", "PUT", [
    Param.new("user_id", "", "path"),
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/api/v1/users/{user_id}", "DELETE", [
    Param.new("user_id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/specification/grpc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
