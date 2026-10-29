require "../../func_spec.cr"

# #3291:
#   named/  - a named inline plugin function keeps its register `prefix`.
#   schema/ - route `schema` (querystring, body, headers; JSON Schema,
#             a same-file constant or TypeBox) declares the route's params.
expected_endpoints = [
  Endpoint.new("/api/tasks", "GET"),
  Endpoint.new("/tasks", "GET", [Param.new("page", "", "query"), Param.new("status", "", "query")]),
  Endpoint.new("/tasks", "POST", [
    Param.new("name", "", "json"), Param.new("assignee", "", "json"), Param.new("x-tenant", "", "header"),
  ]),
  Endpoint.new("/tasks/:id", "PUT", [Param.new("id", "", "path"), Param.new("title", "", "json")]),
]

FunctionalTester.new("fixtures/javascript/fastify_plugin_schema/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
