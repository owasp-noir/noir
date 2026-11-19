require "../../func_spec.cr"

# `@hono/zod-validator`: `zValidator(target, schema)` middleware, inline or
# a same-file schema constant.
expected_endpoints = [
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "json"), Param.new("content", "", "json"), Param.new("draft", "", "query"),
  ]),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
]

FunctionalTester.new("fixtures/javascript/hono_zod_validator/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
