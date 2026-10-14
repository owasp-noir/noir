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
]

FunctionalTester.new("fixtures/php/symfony_route_imports/", {
  :techs     => 2,
  :endpoints => 4,
}, expected_endpoints).perform_tests
