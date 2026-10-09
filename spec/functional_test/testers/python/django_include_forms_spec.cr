require "../../func_spec.cr"

# `include()` of a package urlconf (`api/urls/__init__.py`) and of the
# `(module, app_name)` tuple both keep the mount prefix; neither used to be
# followed, leaving unprefixed routes plus a bare GET on the mount point.
expected_endpoints = [
  Endpoint.new("/api/users/<uuid:id>/", "GET"),
  Endpoint.new("/v1/x/<int:pk>/", "GET"),
]

FunctionalTester.new("fixtures/python/django_include_forms/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
