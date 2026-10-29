require "../../func_spec.cr"

# #3309: an `@hono/zod-openapi` app is detected, and `createRoute({...})`
# routes carry their `request` query / JSON body fields.
expected_endpoints = [
  Endpoint.new("/tasks/{id}", "GET", [Param.new("id", "", "path"), Param.new("verbose", "", "query")]),
  Endpoint.new("/tasks", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/doc", "GET"),
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/javascript/hono_zod_openapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
