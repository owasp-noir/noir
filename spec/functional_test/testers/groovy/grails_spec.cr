require "../../func_spec.cr"

expected_endpoints = [
  # BookController — `def name() { ... }` form with allowedMethods.
  Endpoint.new("/book/index", "GET"),
  Endpoint.new("/book/show", "GET"),
  Endpoint.new("/book/save", "POST"),
  Endpoint.new("/book/update", "PUT"),
  Endpoint.new("/book/update", "PATCH"),
  Endpoint.new("/book/delete", "DELETE"),
  # AuthorController — closure-style and method-style actions.
  Endpoint.new("/author/list", "GET"),
  Endpoint.new("/author/profile", "GET"),
  # TypedController — actions with explicit return types (Grails 3+).
  Endpoint.new("/typed/index", "GET"),
  Endpoint.new("/typed/list", "GET"),
  Endpoint.new("/typed/show", "GET"),
  # ProductController — `static scaffold = X` synthesizes 7 CRUD actions.
  Endpoint.new("/product/index", "GET"),
  Endpoint.new("/product/show", "GET"),
  Endpoint.new("/product/create", "GET"),
  Endpoint.new("/product/save", "POST"),
  Endpoint.new("/product/edit", "GET"),
  Endpoint.new("/product/update", "PUT"),
  Endpoint.new("/product/delete", "DELETE"),
  # UserRestController — `extends RestfulController<T>` inherits 6 REST actions.
  Endpoint.new("/userRest/index", "GET"),
  Endpoint.new("/userRest/show", "GET"),
  Endpoint.new("/userRest/save", "POST"),
  Endpoint.new("/userRest/update", "PUT"),
  Endpoint.new("/userRest/patch", "PATCH"),
  Endpoint.new("/userRest/delete", "DELETE"),
  # UrlMappings — verb-prefixed and verbless paren-form.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/login", "POST"),
  Endpoint.new("/api/users", "POST"),
  # `(resources: 'order')` shortcut → six REST endpoints.
  Endpoint.new("/api/orders", "GET"),
  Endpoint.new("/api/orders", "POST"),
  Endpoint.new("/api/orders/:id", "GET"),
  Endpoint.new("/api/orders/:id", "PUT"),
  Endpoint.new("/api/orders/:id", "PATCH"),
  Endpoint.new("/api/orders/:id", "DELETE"),
  # `group "/v2", { ... }` — prefix propagates to inner mappings.
  Endpoint.new("/v2/items", "GET"),
  # Closure-form mapping with `method = "POST"` assignment.
  Endpoint.new("/api/legacy", "POST"),
  # `name <id>:` prefix on a verb-prefixed mapping is tolerated.
  Endpoint.new("/api/reports", "GET"),
  # `uri:` mapping — still an exposed endpoint despite no controller/action.
  Endpoint.new("/api/legacy-alias", "GET"),
  # Singular `resource:` shortcut — five REST verbs at the path itself.
  Endpoint.new("/api/profile", "GET"),
  Endpoint.new("/api/profile", "POST"),
  Endpoint.new("/api/profile", "PUT"),
  Endpoint.new("/api/profile", "PATCH"),
  Endpoint.new("/api/profile", "DELETE"),
  # `void`-return actions on `ReportController`.
  Endpoint.new("/report/index", "GET"),
  Endpoint.new("/report/show", "GET"),
  # Plugin-style `<Name>UrlMappings.groovy` is also processed.
  Endpoint.new("/plugin/status", "GET"),
]

FunctionalTester.new("fixtures/groovy/grails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
