require "../../func_spec.cr"

# One urlconf `include()`d under two prefixes (the Django docs' URL
# namespaces example, API versions) is served under both.
expected_endpoints = [
  Endpoint.new("/author-polls/", "GET"),
  Endpoint.new("/author-polls/<int:pk>/", "GET", [Param.new("pk", "", "path")]),
  Endpoint.new("/publisher-polls/", "GET"),
  Endpoint.new("/publisher-polls/<int:pk>/", "GET", [Param.new("pk", "", "path")]),
  Endpoint.new("/api/v1/ping/", "GET"),
  Endpoint.new("/api/v2/ping/", "GET"),
]

FunctionalTester.new("fixtures/python/django_include_twice/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
