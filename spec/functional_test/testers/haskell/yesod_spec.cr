require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/blog/:text", "GET", [
    Param.new("text", "Text", "path"),
  ]),
  Endpoint.new("/blog/:text", "POST", [
    Param.new("text", "Text", "path"),
  ]),
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/users/:user_id", "PUT", [
    Param.new("user_id", "UserId", "path"),
  ]),
  Endpoint.new("/api/users/:user_id", "DELETE", [
    Param.new("user_id", "UserId", "path"),
  ]),
  Endpoint.new("/search", "GET"),
  Endpoint.new("/files/*texts", "GET", [
    Param.new("texts", "Texts", "path"),
  ]),
  Endpoint.new("/feed/*texts", "GET", [
    Param.new("texts", "Texts", "path"),
  ]),
  Endpoint.new("/feed/*texts", "POST", [
    Param.new("texts", "Texts", "path"),
  ]),
]

FunctionalTester.new("fixtures/haskell/yesod/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
