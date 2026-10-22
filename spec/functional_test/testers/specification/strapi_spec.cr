require "../../func_spec.cr"

expected_endpoints = [
  # collectionType -> five verbs on the plural name.
  Endpoint.new("/api/articles", "GET", [
    Param.new("populate", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("pagination[page]", "", "query"),
    # Bare attribute names are not Strapi query keys.
    Param.new("filters[title][$eq]", "", "query"),
  ]),
  Endpoint.new("/api/articles", "POST", [
    # Strapi wraps the payload in a data envelope.
    Param.new("data.title", "string", "json"),
    Param.new("data.slug", "string", "json"),
    Param.new("data.body", "string", "json"),
    Param.new("data.views", "int", "json"),
    Param.new("data.featured", "boolean", "json"),
    Param.new("data.publishedAt", "datetime", "json"),
  ]),
  Endpoint.new("/api/articles/{documentId}", "GET", [
    Param.new("documentId", "", "path"),
  ]),
  Endpoint.new("/api/articles/{documentId}", "PUT", [
    Param.new("data.title", "string", "json"),
  ]),
  Endpoint.new("/api/articles/{documentId}", "DELETE"),
  # singleType -> read/update/delete on the singular name, no listing.
  Endpoint.new("/api/homepage", "GET"),
  Endpoint.new("/api/homepage", "PUT", [
    Param.new("data.heading", "string", "json"),
    Param.new("data.subheading", "string", "json"),
  ]),
  Endpoint.new("/api/homepage", "DELETE"),
  # Custom routes from src/api/article/routes/, mounted under /api.
  Endpoint.new("/api/articles/featured", "GET"),
  Endpoint.new("/api/articles/{id}/like", "POST", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/specification/strapi/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
