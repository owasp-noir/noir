require "../../func_spec.cr"

expected_endpoints = [
  # collectionType -> five verbs on the plural name.
  Endpoint.new("/api/articles", "GET", [
    Param.new("populate", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("pagination[page]", "", "query"),
    # Bare attribute names are not Strapi query keys.
    Param.new("filters[title][$eq]", "", "query"),
    Param.new("fields", "", "query"),
    Param.new("filters[body][$eq]", "", "query"),
    Param.new("filters[featured][$eq]", "", "query"),
    Param.new("filters[publishedAt][$eq]", "", "query"),
    Param.new("filters[slug][$eq]", "", "query"),
    Param.new("filters[views][$eq]", "", "query"),
    Param.new("pagination[pageSize]", "", "query"),
    Param.new("status", "", "query"),
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
    Param.new("fields", "", "query"),
    Param.new("populate", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/api/articles/{documentId}", "PUT", [
    Param.new("data.title", "string", "json"),
    Param.new("data.body", "", "json"),
    Param.new("data.featured", "", "json"),
    Param.new("data.slug", "", "json"),
    Param.new("data.views", "", "json"),
    Param.new("data.publishedAt", "", "json"),
    Param.new("documentId", "", "path"),
  ]),
  Endpoint.new("/api/articles/{documentId}", "DELETE", [
    Param.new("documentId", "", "path"),
  ]),
  # singleType -> read/update/delete on the singular name, no listing.
  Endpoint.new("/api/homepage", "GET", [
    Param.new("fields", "", "query"),
    Param.new("populate", "", "query"),
    Param.new("sort", "", "query"),
    Param.new("status", "", "query"),
  ]),
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
