require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/users", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "json"), Param.new("email", "", "json")]),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path"), Param.new("authorization", "", "header")]),
  # `(admin)` is a group and `index` the directory itself.
  Endpoint.new("/health", "GET"),
  Endpoint.new("/files/{path}", "GET", [Param.new("path", "", "path")]),
  # Not routes: `app/index.tsx` is a screen (its `GET` export is ignored)
  # and `lib/proxy+api.ts` sits outside the router root.
]

FunctionalTester.new("fixtures/javascript/expo_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
