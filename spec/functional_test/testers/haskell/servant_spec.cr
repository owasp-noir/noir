require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/users", "GET"),
  Endpoint.new("/v1/users/:userId", "GET", [
    Param.new("userId", "Integer", "path"),
  ]),
  Endpoint.new("/v1/users", "POST", [
    Param.new("body", "User", "body"),
  ]),
  Endpoint.new("/v1/users/:userId", "PUT", [
    Param.new("userId", "Integer", "path"),
    Param.new("body", "User", "body"),
  ]),
  Endpoint.new("/v1/users/:userId", "DELETE", [
    Param.new("userId", "Integer", "path"),
  ]),
  Endpoint.new("/v1/search", "GET", [
    Param.new("q", "Text", "query"),
  ]),
  Endpoint.new("/v1/files/*path", "GET", [
    Param.new("path", "Text", "path"),
  ]),
  Endpoint.new("/v1/secure", "GET", [
    Param.new("X-Token", "Text", "header"),
  ]),
  # MultipartForm produces a body param, with the underlying data type.
  Endpoint.new("/v1/upload", "POST", [
    Param.new("body", "MultipartData", "body"),
  ]),
  # `StreamGet NewlineFraming JSON ...` resolves to a GET endpoint.
  Endpoint.new("/v1/stream", "GET"),
  # `UVerb 'PATCH ...` resolves to a PATCH endpoint.
  Endpoint.new("/v1/uverb", "PATCH"),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/haskell/servant/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
