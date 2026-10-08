require "../../func_spec.cr"

# API Platform resources are class attributes. Operations without their own
# `uriTemplate` inherit the resource's or get the generated `/{plural}` /
# `/{plural}/{id}` path, under `routePrefix` and the `type: api_platform`
# route import's `/api` prefix.
expected_endpoints = [
  # #[ApiResource] defaults
  Endpoint.new("/api/books/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/books", "GET"),
  Endpoint.new("/api/books", "POST"),
  Endpoint.new("/api/books/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/api/books/{id}", "DELETE", [Param.new("id", "", "path")]),
  # shortName + routePrefix + parameters
  Endpoint.new("/api/admin/admin_reviews", "GET", [
    Param.new("rating", "", "query"),
    Param.new("q", "", "query"),
    Param.new("X-Tenant", "", "header"),
  ]),
  Endpoint.new("/api/admin/admin_reviews/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/admin/reviews/{id}/moderate", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/api/admin/reviews/cache", "OPTIONS"),
  # resource-level uriTemplate, NotExposed skipped
  Endpoint.new("/api/books/{bookId}/reviews", "GET", [Param.new("bookId", "", "path")]),
  Endpoint.new("/api/books/{bookId}/reviews", "POST", [Param.new("bookId", "", "path")]),
  Endpoint.new("/api/books/{bookId}/reviews/{id}", "DELETE", [Param.new("bookId", "", "path"), Param.new("id", "", "path")]),
  # standalone operation attributes behind a namespace alias
  Endpoint.new("/api/categories/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/api/categories", "GET"),
  Endpoint.new("/api/categories/import", "POST"),
  # a standalone operation joins the preceding #[ApiResource]
  Endpoint.new("/api/catalog/publishers", "GET"),
  # identifier property name
  Endpoint.new("/api/shops", "GET"),
  Endpoint.new("/api/shops/{code}", "GET", [Param.new("code", "", "path")]),
  # enum resources only get GetCollection + Get
  Endpoint.new("/api/book_conditions", "GET"),
  Endpoint.new("/api/book_conditions/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/php/api_platform/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("php_api_platform"),
}).perform_tests
