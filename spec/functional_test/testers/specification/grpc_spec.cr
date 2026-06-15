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
  # Stream RPC (server-streaming) - pure gRPC
  Endpoint.new("/example.v1.UserService/StreamUsers", "POST", [
    Param.new("page", "", "json"),
    Param.new("page_size", "", "json"),
  ]),
  # Search with nested message fields
  Endpoint.new("/api/v1/users/search", "GET", [
    Param.new("query", "", "query"),
    Param.new("filter", "", "query"),
    Param.new("page", "", "query"),
  ]),
  # Additional bindings - primary
  Endpoint.new("/api/v1/users/{user_id}/profile", "GET", [
    Param.new("user_id", "", "path"),
    Param.new("name", "", "query"),
  ]),
  # Additional bindings - secondary
  Endpoint.new("/api/v2/users/{user_id}", "GET", [
    Param.new("user_id", "", "path"),
    Param.new("name", "", "query"),
  ]),
  # No-package service (health.proto)
  Endpoint.new("/HealthService/Check", "POST", [
    Param.new("service", "", "json"),
  ]),
  # Specific body field - remaining fields become query params
  Endpoint.new("/api/v1/users/{user_id}", "PATCH", [
    Param.new("user_id", "", "path"),
    Param.new("display_name", "", "json"),
    Param.new("bio", "", "query"),
  ]),
  # Qualified response type (google.protobuf.Empty)
  Endpoint.new("/api/v1/users/{user_id}/ping", "POST", [
    Param.new("user_id", "", "path"),
    Param.new("name", "", "json"),
  ]),
  # Path parameter with resource pattern {name=projects/*/locations/*}
  Endpoint.new("/api/v1/{name=projects/*/locations/*}/resource", "GET", [
    Param.new("name", "", "path"),
    Param.new("user_id", "", "query"),
  ]),
  # Commented-out services/methods must be ignored; only the real rpc remains.
  Endpoint.new("/comments.v1.NoteService/CreateNote", "POST", [
    Param.new("note_id", "", "json"),
    Param.new("body", "", "json"),
  ]),
  # Colon-form additional_bindings: primary + secondary binding.
  Endpoint.new("/v1/items/{item_id}", "GET", [
    Param.new("item_id", "", "path"),
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/v1/items/by-name/{name}", "GET", [
    Param.new("name", "", "path"),
    Param.new("item_id", "", "query"),
  ]),
  # Array-form additional_bindings: primary PUT + two PATCH bindings.
  Endpoint.new("/v1/items/{item_id}", "PUT", [
    Param.new("item_id", "", "path"),
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/v1/items/{item_id}", "PATCH", [
    Param.new("item_id", "", "path"),
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/v2/items/{item_id}", "PATCH", [
    Param.new("item_id", "", "path"),
    Param.new("name", "", "json"),
  ]),
  # custom: { kind, path } maps to a non-standard HTTP method (HEAD).
  Endpoint.new("/v1/items/{item_id}/watch", "HEAD", [
    Param.new("item_id", "", "path"),
  ]),
  # Request message imported from another .proto and referenced by its
  # fully-qualified name: `city` resolves to a query param across files.
  Endpoint.new("/v1/addresses/{street}", "GET", [
    Param.new("street", "", "path"),
    Param.new("city", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/specification/grpc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
