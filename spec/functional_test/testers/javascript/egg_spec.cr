require "../../func_spec.cr"

# The `test/fixtures/apps/demo` router belongs to a package.json that does not
# name egg, so it contributes nothing.
FunctionalTester.new("fixtures/javascript/egg/", {
  :techs     => 1,
  :endpoints => 26,
}, [
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
  ]),
  Endpoint.new("/api/login", "POST", [
    Param.new("username", "", "json"),
    Param.new("password", "", "json"),
    Param.new("csrfToken", "", "cookie"),
  ]),
  Endpoint.new("/api/users/:id", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("x-admin-token", "", "header"),
  ]),
  # `resources` registers only the actions posts.ts defines; its commented-out
  # `destroy` is not one.
  Endpoint.new("/api/posts", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/posts", "POST", [Param.new("title", "", "json")]),
  Endpoint.new("/api/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/:id", "PUT", [Param.new("id", "", "path")]),
  # A resource whose actions are all inherited registers every action.
  Endpoint.new("/api/tags", "GET"),
  Endpoint.new("/api/tags/new", "GET"),
  Endpoint.new("/api/tags/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/tags/:id", "DELETE", [Param.new("id", "", "path")]),
  # koa-router registers `redirect` through `all`.
  Endpoint.new("/home", "GET"),
  Endpoint.new("/home", "POST"),
  Endpoint.new("/home", "OPTIONS"),
  Endpoint.new("/health", "GET", [Param.new("verbose", "", "query")]),
  Endpoint.new("/admin/reports", "POST", [Param.new("period", "", "json")]),
]).perform_tests
