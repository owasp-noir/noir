require "../../func_spec.cr"

# `{var=pattern}` path templates are transcoding syntax. The URL is spelled the
# way a client can request it: literals stay, the last wildcard takes the
# variable's name, earlier wildcards become `{wildcard}`, `{wildcard2}`, ...
# The variable is still the one declared path param.
expected_endpoints = [
  Endpoint.new("/api/attachments/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/api/memos/{parent}/comments", "GET", [
    Param.new("parent", "", "path"),
  ]),
  Endpoint.new("/v1/projects/{wildcard}/serviceAccounts/{wildcard2}/keys/{name}:inspect", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/v1/publishers/{wildcard}/books/{book.name}", "PATCH", [
    Param.new("book.name", "", "path"),
    Param.new("book", "", "json"),
  ]),
  Endpoint.new("/v1/{resource}:testIamPermissions", "POST", [
    Param.new("resource", "", "path"),
  ]),
  Endpoint.new("/v1/repeat/a/{first}/b/{second}", "GET", [
    Param.new("first", "", "path"),
    Param.new("second", "", "path"),
  ]),
  # No wildcard: the client requests the literal.
  Endpoint.new("/v1/operations", "GET", [
    Param.new("name", "", "path"),
  ]),
  # A bare `{var}` is already a plain placeholder.
  Endpoint.new("/v1/plain/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/specification/grpc_path_template/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
