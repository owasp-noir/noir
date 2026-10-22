require "../../func_spec.cr"

# `readBody` / `getQuery` with a TypeScript type argument.
expected_endpoints = [
  Endpoint.new("/api/login", "POST", [
    Param.new("email", "", "body"),
    Param.new("password", "", "body"),
  ]),
  Endpoint.new("/api/search", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/profile", "PATCH", [
    Param.new("nickname", "", "body"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nuxtjs_generics/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
