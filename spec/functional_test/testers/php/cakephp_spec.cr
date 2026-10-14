require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/pages/*", "GET"),
  Endpoint.new("/about", "GET"),
  Endpoint.new("/articles", "GET"),
  Endpoint.new("/articles", "POST"),
  Endpoint.new("/articles/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/articles/{id}", "DELETE", [Param.new("id", "", "path")]),
  # resources() honours only (RouteBuilder map keys)
  Endpoint.new("/comments", "GET"),
  Endpoint.new("/comments/{id}", "GET", [Param.new("id", "", "path")]),
  # legacy _method in the options argument
  Endpoint.new("/legacy-post", "POST"),
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/login", "POST"),
  # connect()->setMethods([...]) is honored instead of defaulting to GET
  Endpoint.new("/logout", "POST"),
  Endpoint.new("/sessions/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/sessions/{id}", "DELETE", [Param.new("id", "", "path")]),
  # prefix() opens a prefixed scope like scope()
  Endpoint.new("/groups/{id}", "GET", [Param.new("id", "", "path")]),
  # prefix() with ['path' => '/v1.0'] mounts under the path option, not /v10.
  # (The sibling `config/routes.php.twig` Bake template's `{{ plugin }}` routes
  # are ignored entirely — a `.twig` file is not a routes file.)
  Endpoint.new("/v1.0/status", "GET"),
  # Static Router facade form
  Endpoint.new("/legacy/ping", "GET"),
  # Dasherized prefix/resources names; nested resources() callback
  Endpoint.new("/super-admin/reports", "GET"),
  Endpoint.new("/api/blog-posts", "GET"),
  Endpoint.new("/api/blog-posts", "POST"),
  Endpoint.new("/api/blog-posts/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/blog-posts/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/blog-posts/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/api/blog-posts/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/blog-posts/{blog_post_id}/replies", "GET", [Param.new("blog_post_id", "", "path")]),
  # Typed closure scope
  Endpoint.new("/typed/ping", "GET"),
]

FunctionalTester.new("fixtures/php/cakephp/", {
  :techs     => 2,  # Detection still sees php_cakephp and php_pure
  :endpoints => 30, # Analysis suppresses redundant php_pure file endpoints
}, expected_endpoints).perform_tests
