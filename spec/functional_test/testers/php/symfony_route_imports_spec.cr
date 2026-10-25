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
]

FunctionalTester.new("fixtures/php/symfony_route_imports/", {
  :techs     => 2,
  :endpoints => 6,
}, expected_endpoints).perform_tests
