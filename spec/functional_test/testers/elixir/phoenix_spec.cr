require "../../func_spec.cr"

expected_endpoints = [
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
  Endpoint.new("/api/accounts/:id", "GET", [Param.new("include", "", "query"), Param.new("x-api-version", "", "header"), Param.new("id", "", "path")]),
  Endpoint.new("/api/page", "POST", [Param.new("q", "", "query"), Param.new("page", "", "form"), Param.new("limit", "", "form")]),
  # Plug-style routes (the controller is a Plug, the 3rd arg is opts not an
  # `:action` atom). The HTTP-client calls in api_client.ex must NOT add
  # phantom endpoints.
  Endpoint.new("/api/openapi", "GET"),
  Endpoint.new("/api/swaggerui", "GET"),
  Endpoint.new("/api/hooks", "POST", [Param.new("q", "", "query"), Param.new("page", "", "form"), Param.new("limit", "", "form")]),
  Endpoint.new("/api/hooks", "PUT", [Param.new("q", "", "query"), Param.new("page", "", "form"), Param.new("limit", "", "form")]),
  Endpoint.new("/dev/dashboard", "GET"),
  Endpoint.new("/dev/mailbox", "GET"),
  # Nested resources under a scope: child mounts on the parent's
  # `/:podcast_id` member segment; `only:` behind `as:` still applies.
  Endpoint.new("/admin/podcasts", "GET"),
  Endpoint.new("/admin/podcasts/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/podcasts/:podcast_id/episodes", "GET", [Param.new("podcast_id", "", "path")]),
  # Parenthesised call form + singleton resource (no `/:id` member)
  Endpoint.new("/account/session", "POST"),
  Endpoint.new("/account/session", "DELETE"),
  # `param:` renames the member capture
  Endpoint.new("/account/keys/:key_id", "GET", [Param.new("key_id", "", "path")]),
  Endpoint.new("/account/keys/:key_id", "DELETE", [Param.new("key_id", "", "path")]),
  # Macro-generated routes with unquoted scope/controller defaults
  Endpoint.new("/macro-admin-v2/dashboard", "GET"),
  Endpoint.new("/macro-admin-v2/dashboard", "OPTIONS"),
]

FunctionalTester.new("fixtures/elixir/phoenix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
