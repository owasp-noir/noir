require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/api/v1/users", "GET"),
  Endpoint.new("/api/v1/users", "POST"),
  Endpoint.new("/api/v1/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/blog/posts", "GET"),
  Endpoint.new("/api/v1/blog/posts", "POST"),
  Endpoint.new("/api/v1/blog/posts/:postId", "PATCH", [Param.new("postId", "", "path")]),
  # `Route.resource('articles', ...).apiOnly()` — the API resource bundle.
  Endpoint.new("/articles", "GET"),
  Endpoint.new("/articles", "POST"),
  Endpoint.new("/articles/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/:id", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/:id", "DELETE", [Param.new("id", "", "path")]),
  # `.only(['index', 'show'])` — restricts to two of the five.
  Endpoint.new("/tags", "GET"),
  Endpoint.new("/tags/:id", "GET", [Param.new("id", "", "path")]),
  # `Route.any(...)` fans out to GET / POST / PUT / DELETE / PATCH.
  Endpoint.new("/wildcard", "GET"),
  Endpoint.new("/wildcard", "POST"),
  Endpoint.new("/wildcard", "PUT"),
  Endpoint.new("/wildcard", "DELETE"),
  Endpoint.new("/wildcard", "PATCH"),
]

FunctionalTester.new("fixtures/javascript/adonisjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
