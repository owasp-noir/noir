require "../../func_spec.cr"

# Regression: a reusable Django app (or any project scanned at the
# app level) ships `urls.py` with `urlpatterns` but no project
# `settings.py` declaring `ROOT_URLCONF`. The ROOT_URLCONF-anchored
# pass finds no root, so before the orphan-urlconf fallback the whole
# app mapped to zero endpoints. Paths are app-relative because there
# is no host project to supply a mount prefix.
extracted_endpoints = [
  Endpoint.new("/api/ping/", "GET"),
  Endpoint.new("/api/items/", "GET"),
  Endpoint.new("/api/items/<int:item_id>/", "GET"),
]

FunctionalTester.new("fixtures/python/django_app_urls/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints).perform_tests
