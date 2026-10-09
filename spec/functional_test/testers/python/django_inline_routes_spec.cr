require "../../func_spec.cr"

# A URLconf may hold several `path()` / `re_path()` calls on one source
# line, either as siblings or as the body of an inline `include([...])`.
# Only the first call on each line used to survive.
extracted_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about/", "GET"),
  Endpoint.new("/items/<int:pk>/", "GET", [
    Param.new("pk", "", "path"),
  ]),
  Endpoint.new("/api/users/", "GET"),
  Endpoint.new("/api/teams/", "GET"),
  Endpoint.new("/api/ping/", "GET"),
]

FunctionalTester.new("fixtures/python/django_inline_routes/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints).perform_tests
