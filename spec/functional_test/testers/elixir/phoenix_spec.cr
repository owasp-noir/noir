require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/page", "GET"),
  Endpoint.new("/page", "POST"),
  Endpoint.new("/page", "PUT"),
  Endpoint.new("/page", "PATCH"),
  Endpoint.new("/page", "DELETE"),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/live", "GET"),
  Endpoint.new("/phoenix/live_reload/socket", "GET"),
  # Path parameter routes
  Endpoint.new("/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:user_id/posts/:id", "GET", [Param.new("user_id", "", "path"), Param.new("id", "", "path")]),
  # Wildcard parameter routes
  Endpoint.new("/files/*path", "GET", [Param.new("path", "", "path")]),
  # LiveView routes
  Endpoint.new("/live/users", "GET"),
  Endpoint.new("/live/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/live/users/:id/edit", "GET", [Param.new("id", "", "path")]),
  # Resources routes
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts", "POST"),
  Endpoint.new("/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/new", "GET"),
  Endpoint.new("/posts/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/comments", "GET"),
  Endpoint.new("/comments/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/elixir/phoenix/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
