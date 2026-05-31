require "../../func_spec.cr"

# Regression: a reusable Django app (or any project scanned at the app
# level) ships `urls.py` / a `urls/` package with `urlpatterns` but no
# project `settings.py` declaring `ROOT_URLCONF`. The ROOT_URLCONF-
# anchored pass finds no root, so before the orphan-urlconf fallback
# the whole app mapped to zero endpoints. Paths are app-relative
# because there is no host project to supply a mount prefix.
#
# `blog/urls/__init__.py` also `include()`s a sibling module, locking
# in the fallback's prefix nesting and visited-dedup: the sibling's
# `dashboard/` surfaces once as `/admin/dashboard/` (mounted under the
# include prefix), never as a bare `/dashboard/` from processing
# `admin.py` as its own root — the `:endpoints => 5` count enforces it.
extracted_endpoints = [
  Endpoint.new("/api/ping/", "GET"),
  Endpoint.new("/api/items/", "GET"),
  Endpoint.new("/api/items/<int:item_id>/", "GET"),
  Endpoint.new("/posts/", "GET"),
  Endpoint.new("/admin/dashboard/", "GET"),
]

FunctionalTester.new("fixtures/python/django_app_urls/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints).perform_tests
