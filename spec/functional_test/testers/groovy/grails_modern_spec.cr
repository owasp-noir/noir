require "../../func_spec.cr"

expected_endpoints = [
  # ApiController — public actions only. The private/protected/static helpers
  # (`buildModel`, `formatBody`, `counter`) and the JavaBean getter
  # (`getDisplayName`) must not surface as endpoints.
  Endpoint.new("/api/index", "GET"),
  Endpoint.new("/api/save", "POST"),
  Endpoint.new("/api/list", "GET"),
  # UrlMappings under `grails-app/controllers/` (Grails 3+ layout) is now
  # scanned. `${imageId}` GString translated to `:imageId`; the `(.${format})`
  # content-format suffix is stripped.
  Endpoint.new("/image/:imageId", "GET", [Param.new("imageId", "", "path")]),
  # `action = [GET: 'show', PUT: 'update']` → one endpoint per verb.
  Endpoint.new("/api/v1/widget/:id", "GET"),
  Endpoint.new("/api/v1/widget/:id", "PUT"),
  # `(resources: 'book')` shortcut → six REST endpoints.
  Endpoint.new("/api/v1/books", "GET"),
  Endpoint.new("/api/v1/books", "POST"),
  Endpoint.new("/api/v1/books/:id", "GET"),
  Endpoint.new("/api/v1/books/:id", "PUT"),
  Endpoint.new("/api/v1/books/:id", "PATCH"),
  Endpoint.new("/api/v1/books/:id", "DELETE"),
  # `"404"`/`"500"` response-code mappings are error pages, not endpoints.
]

FunctionalTester.new("fixtures/groovy/grails_modern/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
