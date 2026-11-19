require "../../func_spec.cr"

# `const body = await c.req.json()`, `c.req.json<T>()`, `c.req.parseBody()`
# bound to a local, and `const { a } = c.req.query()`.
expected_endpoints = [
  Endpoint.new("/h00-control", "POST", [Param.new("title", "", "json")]),
  Endpoint.new("/h01-var", "POST", [Param.new("title", "", "json"), Param.new("slug", "", "json")]),
  Endpoint.new("/h02-var-destructure", "POST", [Param.new("email", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/h03-typed", "POST", [Param.new("name", "", "json"), Param.new("age", "", "json")]),
  Endpoint.new("/h04-form-var", "POST", [Param.new("avatar", "", "form"), Param.new("caption", "", "form")]),
  Endpoint.new("/h05-query-destructure", "GET", [Param.new("page", "", "query"), Param.new("limit", "", "query")]),
]

FunctionalTester.new("fixtures/javascript/hono_request_alias/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
