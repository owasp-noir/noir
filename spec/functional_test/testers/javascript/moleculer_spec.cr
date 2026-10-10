require "../../func_spec.cr"

# lib/fake-gateway.js has gateway-shaped `routes[].aliases` without the
# moleculer-web mixin, so `/nope/leak` is not reported; test/api.spec.js
# is a test, so `/test-only/secret` is not either.
FunctionalTester.new("fixtures/javascript/moleculer/", {
  :techs     => 1,
  :endpoints => 17,
}, [
  Endpoint.new("/api/users", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("name", "", "json"), Param.new("email", "", "json")]),
  Endpoint.new("/api/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/health", "ANY"),
  Endpoint.new("/api/hi", "GET"),
  # `REST posts` expands to the six CRUD routes.
  Endpoint.new("/api/posts", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/posts", "POST", [Param.new("title", "", "json"), Param.new("body", "", "json")]),
  Endpoint.new("/api/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/api/posts/:id", "DELETE", [Param.new("id", "", "path")]),
  # `autoAliases` maps every action's `rest:` under the service name.
  Endpoint.new("/auto/users", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/auto/users", "POST", [Param.new("name", "", "json"), Param.new("email", "", "json")]),
  Endpoint.new("/auto/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/auto/v2/orders/find", "ANY"),
  # `settings.rest` as an array mounts the service under each base path.
  Endpoint.new("/auto/items/:sku", "GET", [Param.new("sku", "", "path"), Param.new("s", "", "query")]),
  Endpoint.new("/auto/things/:sku", "GET", [Param.new("sku", "", "path"), Param.new("s", "", "query")]),
]).perform_tests
