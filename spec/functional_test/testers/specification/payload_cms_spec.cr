require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/posts", "GET", [
    Param.new("depth", "", "query"),
    Param.new("where", "", "query"),
    # Payload filters through the operator form, not a bare field name.
    Param.new("where[title][equals]", "", "query"),
  ]),
  Endpoint.new("/api/posts", "POST", [
    Param.new("title", "string", "json"),
    # `views` and `featured` sit inside a `row` wrapper, which is layout
    # only - they belong at the top level of the document.
    Param.new("views", "number", "json"),
    Param.new("featured", "boolean", "json"),
    # A `group` is named, so its children nest under it.
    Param.new("meta.description", "string", "json"),
    Param.new("publishedAt", "datetime", "json"),
  ]),
  Endpoint.new("/api/posts", "PATCH", [
    Param.new("title", "string", "json"),
    Param.new("where", "", "query"),
  ]),
  Endpoint.new("/api/posts", "DELETE", [
    Param.new("where", "", "query"),
  ]),
  Endpoint.new("/api/posts/count", "GET"),
  Endpoint.new("/api/posts/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/posts/{id}", "PATCH", [
    Param.new("title", "string", "json"),
  ]),
  Endpoint.new("/api/posts/{id}", "DELETE"),
  # versions: { drafts: true }
  Endpoint.new("/api/posts/versions", "GET"),
  Endpoint.new("/api/posts/versions/{id}", "GET"),
  Endpoint.new("/api/posts/versions/{id}", "POST"),
  # endpoints: [{ path: '/:id/tracking', method: 'get' }]
  Endpoint.new("/api/posts/{id}/tracking", "GET"),

  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST", [
    Param.new("name", "string", "json"),
  ]),
  Endpoint.new("/api/users", "PATCH"),
  Endpoint.new("/api/users", "DELETE"),
  Endpoint.new("/api/users/count", "GET"),
  Endpoint.new("/api/users/{id}", "GET"),
  Endpoint.new("/api/users/{id}", "PATCH"),
  Endpoint.new("/api/users/{id}", "DELETE"),
  # auth: true unlocks the whole credential surface.
  Endpoint.new("/api/users/login", "POST", [
    Param.new("email", "string", "json"),
    Param.new("password", "string", "json"),
  ]),
  Endpoint.new("/api/users/logout", "POST"),
  Endpoint.new("/api/users/refresh-token", "POST"),
  Endpoint.new("/api/users/me", "GET"),
  Endpoint.new("/api/users/forgot-password", "POST", [
    Param.new("email", "string", "json"),
  ]),
  Endpoint.new("/api/users/reset-password", "POST", [
    Param.new("token", "string", "json"),
    Param.new("password", "string", "json"),
  ]),
  Endpoint.new("/api/users/unlock", "POST"),

  # Globals are read with GET and written with POST.
  Endpoint.new("/api/globals/site-settings", "GET"),
  Endpoint.new("/api/globals/site-settings", "POST", [
    Param.new("siteName", "string", "json"),
    Param.new("maintenance", "boolean", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/payload_cms/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
