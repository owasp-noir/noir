require "../../func_spec.cr"

expected_endpoints = [
  # Java DSL (RestRoutes.java) — rest routes sit under contextPath("/api").
  Endpoint.new("/api/users/{id}", "GET"),
  Endpoint.new("/api/users", "POST", [Param.new("body", "User", "json")]),
  Endpoint.new("/api/users/{id}", "DELETE"),
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/api/orders", "GET", [Param.new("status", "", "query")]),
  Endpoint.new("/api/orders/{id}", "PUT", [
    Param.new("X-Token", "", "header"),
    Param.new("body", "Order", "json"),
  ]),
  Endpoint.new("/api/ping", "GET"),
  Endpoint.new("/legacy", "ANY"),
  Endpoint.new("/upload", "POST"),
  Endpoint.new("/upload", "PUT"),
  # XML DSL (camel-context.xml)
  Endpoint.new("/api/xml/items/{id}", "GET"),
  Endpoint.new("/api/xml/items", "POST", [
    Param.new("dryRun", "", "query"),
    Param.new("body", "Item", "json"),
  ]),
  Endpoint.new("/xml/health", "GET"),
  # YAML DSL (routes.camel.yaml)
  Endpoint.new("/api/yaml/books/{isbn}", "GET"),
  Endpoint.new("/api/yaml/books", "POST", [
    Param.new("X-Trace", "", "header"),
    Param.new("body", "Book", "json"),
  ]),
  Endpoint.new("/yaml/status", "GET"),
  Endpoint.new("/yaml/raw", "ANY"),
]

FunctionalTester.new("fixtures/java/camel/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

# `camel.rest.context-path` prefixes REST DSL routes of its own module only
# (application.properties at the root, application.yml in yml-module); plain
# HTTP consumers stay at the server root.
properties_endpoints = [
  Endpoint.new("/svc/v1/status", "GET"),
  Endpoint.new("/raw", "ANY"),
  Endpoint.new("/yml/items", "GET"),
]

FunctionalTester.new("fixtures/java/camel_properties/", {
  :techs     => 1,
  :endpoints => properties_endpoints.size,
}, properties_endpoints).perform_tests
