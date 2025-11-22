require "../../func_spec.cr"

extected_endpoints = [
  # Basic HTTP methods with query and form parameters
  Endpoint.new("/page", "GET", [Param.new("q", "", "query"), Param.new("page", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/page", "POST", [Param.new("q", "", "query"), Param.new("page", "", "form"), Param.new("limit", "", "form")]),
  Endpoint.new("/page", "PUT", [Param.new("q", "", "query"), Param.new("page", "", "form"), Param.new("limit", "", "form")]),
  Endpoint.new("/page", "PATCH", [Param.new("q", "", "query"), Param.new("page", "", "form"), Param.new("limit", "", "form")]),
  Endpoint.new("/page", "DELETE", [Param.new("q", "", "query"), Param.new("page", "", "form"), Param.new("limit", "", "form")]),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/live", "GET"),
  Endpoint.new("/phoenix/live_reload/socket", "GET"),
  # Path parameter routes with headers
  Endpoint.new("/users/:id", "GET", [Param.new("authorization", "", "header"), Param.new("x-api-key", "", "header"), Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "PUT", [Param.new("name", "", "form"), Param.new("email", "", "form"), Param.new("age", "", "form"), Param.new("session_id", "", "cookie"), Param.new("user_preference", "", "cookie"), Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:user_id/posts/:id", "GET", [Param.new("user_id", "", "path"), Param.new("id", "", "path")]),
  # Wildcard parameter routes
  Endpoint.new("/files/*path", "GET", [Param.new("path", "", "path")]),
  # LiveView routes
  Endpoint.new("/live/users", "GET"),
  Endpoint.new("/live/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/live/users/:id/edit", "GET", [Param.new("id", "", "path")]),
  # Resources routes with query and form parameters
  Endpoint.new("/posts", "GET", [Param.new("category", "", "query"), Param.new("sort", "", "query")]),
  Endpoint.new("/posts", "POST", [Param.new("title", "", "form"), Param.new("content", "", "form"), Param.new("tags", "", "form")]),
  Endpoint.new("/posts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "PUT", [Param.new("title", "", "form"), Param.new("content", "", "form"), Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "PATCH", [Param.new("title", "", "form"), Param.new("content", "", "form"), Param.new("id", "", "path")]),
  Endpoint.new("/posts/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/new", "GET"),
  Endpoint.new("/posts/:id/edit", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/comments", "GET", [Param.new("post_id", "", "query")]),
  Endpoint.new("/comments/:id", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/elixir/phoenix/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
