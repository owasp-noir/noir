require "../../func_spec.cr"

# Attribute routes under a directory imported by a YAML route config
# (`resource: ../src/Controller/Api/`, `type: attribute`) take that import's
# `prefix`.
expected_endpoints = [
  Endpoint.new("/api/v1/products/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/{_locale}", "GET", [Param.new("_locale", "", "path")]),
  # Outside every import: unprefixed.
  Endpoint.new("/status", "GET"),
  # Plain YAML route.
  Endpoint.new("/health", "GET"),
  # Re-imported by a later import of the same routing file: Symfony replaces
  # routes by name, so the /{_locale} copy is gone; a `name_prefix` import
  # keeps its own copy.
  Endpoint.new("/auth/sso/login", "GET"),
  Endpoint.new("/old/sso/login", "GET"),
  # A localized prefix renames routes `name.<locale>`: no collision with a
  # plain-prefix import.
  Endpoint.new("/en/sso/login", "GET"),
  # The later `site` import excludes Admin/, so it never replaces /admin.
  Endpoint.new("/admin/panel", "GET"),
]

FunctionalTester.new("fixtures/php/symfony_route_imports/", {
  :techs     => 2,
  :endpoints => 8,
}, expected_endpoints).perform_tests
