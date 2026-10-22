require "../../func_spec.cr"

# File-routed Pages Functions: `[id]` and `[[path]]` become `{id}` / `{path}`,
# `index` maps to its directory, `_middleware` and helpers are not routes, and
# a `functions/` dir outside the project root is ignored.
FunctionalTester.new("fixtures/javascript/cloudflare_pages/", {
  :techs     => 1,
  :endpoints => 7,
}, [
  Endpoint.new("/", "ANY"),
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/api/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("reason", "", "query"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
  # `onRequest` next to a verb export serves the remaining methods.
  Endpoint.new("/api/users", "ANY"),
  # A catch-all `onRequest` narrowed by its `request.method` checks.
  Endpoint.new("/api/files/{path}", "GET", [
    Param.new("path", "", "path"),
    Param.new("cookie", "", "header"),
  ]),
  Endpoint.new("/api/files/{path}", "PUT", [
    Param.new("path", "", "path"),
    Param.new("cookie", "", "header"),
  ]),
]).perform_tests
