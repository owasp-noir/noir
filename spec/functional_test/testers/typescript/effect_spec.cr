require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  # Payload schema declared as a constant.
  Endpoint.new("/users", "POST", [Param.new("name", "", "json"), Param.new("email", "", "json")]),
  Endpoint.new("/users/search", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query")]),
  # Tagged-template path: `${idParam}` names `HttpApiSchema.param("id", ...)`.
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("x-api-key", "", "header"),
    Param.new("name", "", "json"),
  ]),
  # `HttpApiGroup.prefix` on the group chain, and on a group added by name.
  Endpoint.new("/system/health", "GET"),
  Endpoint.new("/admin/stats", "GET"),
]

FunctionalTester.new("fixtures/typescript/effect_httpapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
