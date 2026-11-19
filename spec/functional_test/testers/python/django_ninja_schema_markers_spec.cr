require "../../func_spec.cr"

# `Query[Schema]` / `Schema = Query(...)` / `Form[Schema]` take the schema's
# fields from that location (`Field(alias=)` renames one); `Path[Schema]`
# fields are the URL's own path params.
query = %w[limit offset query categories].map { |name| Param.new(name, "", "query") }
expected_endpoints = [
  Endpoint.new("/api/filter", "GET", query),
  Endpoint.new("/api/filter-legacy", "GET", query),
  Endpoint.new("/api/events/{year}/{month}/{day}", "GET", %w[year month day].map { |name| Param.new(name, "", "path") }),
  Endpoint.new("/api/items", "POST", %w[name description price].map { |name| Param.new(name, "", "form") }),
  Endpoint.new("/api/items-json", "POST", %w[name description price].map { |name| Param.new(name, "", "json") }),
  # From the Django analyzer: `path("api/", api.urls)`.
  Endpoint.new("/api/", "GET"),
]

FunctionalTester.new("fixtures/python/django_ninja_schema_markers/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
