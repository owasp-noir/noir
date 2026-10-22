require "../../func_spec.cr"

expected_endpoints = [
  # String controller binding, no `@method` -> defaults to `__call__`.
  Endpoint.new("/", "GET"),

  # Class/method controller binding.
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
    Param.new("email", "", "query"),
  ]),

  # Required + typed (`:integer`) path parameters — both map to the same
  # `show` handler.
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/typed/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),

  # Optional path parameter (`?term`) alongside an unrelated query input
  # read inside the handler.
  Endpoint.new("/search/{term}", "GET", [
    Param.new("term", "", "path"),
    Param.new("sort", "", "query"),
  ]),

  # Nested Route.group: prefixes compose outer -> inner.
  Endpoint.new("/account/settings", "GET", [
    Param.new("theme", "", "query"),
  ]),
  Endpoint.new("/account/security/profile", "PUT", [
    Param.new("bio", "", "query"),
  ]),

  # Group whose inner route is bare "/" must not leave a trailing slash.
  Endpoint.new("/admin/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/admin/users", "POST", [
    Param.new("username", "", "query"),
  ]),

  # Route.resource("posts", "PostController") -> 7 REST routes.
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts/create", "GET"),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/posts/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/{id}/edit", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/posts/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/posts/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # Route.api("api/posts", "PostController") -> 5 REST-API routes.
  Endpoint.new("/api/posts", "GET"),
  Endpoint.new("/api/posts", "POST", [
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/api/posts/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/posts/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/api/posts/{id}", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/api/posts/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # Specialized helpers.
  Endpoint.new("/about", "GET"),
  Endpoint.new("/old-home", "GET"),
  Endpoint.new("/legacy", "GET"),

  # Route.any -> all six verbs.
  Endpoint.new("/webhook", "GET", [Param.new("X-Webhook-Token", "", "header")]),
  Endpoint.new("/webhook", "POST", [Param.new("X-Webhook-Token", "", "header")]),
  Endpoint.new("/webhook", "PUT", [Param.new("X-Webhook-Token", "", "header")]),
  Endpoint.new("/webhook", "PATCH", [Param.new("X-Webhook-Token", "", "header")]),
  Endpoint.new("/webhook", "DELETE", [Param.new("X-Webhook-Token", "", "header")]),
  Endpoint.new("/webhook", "OPTIONS", [Param.new("X-Webhook-Token", "", "header")]),

  # Route.match(["put", "patch"], ...).
  Endpoint.new("/users/{id}/touch", "PUT", [
    Param.new("id", "", "path"),
    Param.new("session_id", "", "cookie"),
  ]),
  Endpoint.new("/users/{id}/touch", "PATCH", [
    Param.new("id", "", "path"),
    Param.new("session_id", "", "cookie"),
  ]),

  # Unresolvable controller reference — still surfaces a bare endpoint.
  Endpoint.new("/health", "GET"),
]

FunctionalTester.new("fixtures/python/masonite/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
