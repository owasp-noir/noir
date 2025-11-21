require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/protected", "GET", [Param.new("authorization", "", "header"), Param.new("x-api-key", "", "header")]),
  Endpoint.new("/profile", "GET", [Param.new("session_id", "", "cookie"), Param.new("user_preference", "", "cookie")]),
  Endpoint.new("/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id/profile", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/health", "HEAD"),
  Endpoint.new("/api/*path", "OPTIONS", [Param.new("path", "", "path")]),
  Endpoint.new("/api", "GET"), # This is from the forward statement
  Endpoint.new("/webhook", "POST"),
  Endpoint.new("/webhook", "PUT"),
  Endpoint.new("/simple", "GET"),
  # ApiRouter endpoints
  Endpoint.new("/status", "GET"),
  Endpoint.new("/data", "POST"),
  Endpoint.new("/data/:type", "GET", [Param.new("type", "", "path")]),
  Endpoint.new("/search/api", "GET", [Param.new("query", "", "query"), Param.new("page", "", "query")]),
  Endpoint.new("/api/create", "POST", [Param.new("title", "", "form"), Param.new("description", "", "form")]),
  Endpoint.new("/api/secured", "GET", [Param.new("x-api-token", "", "header"), Param.new("authorization", "", "header")]),
  Endpoint.new("/api/session", "GET", [Param.new("api_token", "", "cookie"), Param.new("api_user", "", "cookie")]),
]

FunctionalTester.new("fixtures/elixir/plug/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
