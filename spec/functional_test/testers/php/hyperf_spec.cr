require "../../func_spec.cr"

expected_endpoints = [
  # Annotation routes from UserController
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("X-Auth-Token", "", "header"),
  ]),
  Endpoint.new("/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
    Param.new("X-Auth-Token", "", "header"),
  ]),
  # Procedural routes from config/routes.php
  Endpoint.new("/items", "GET"),
  Endpoint.new("/items", "POST"),
  Endpoint.new("/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
  ]),
  Endpoint.new("/api/v1/me", "GET"),
  Endpoint.new("/api/v1/login", "POST"),
  Endpoint.new("/api/v1/admin/users/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/php/hyperf/", {
  :techs     => 2,  # Detection still sees php_hyperf and php_pure
  :endpoints => 10, # Analysis suppresses redundant php_pure entries
}, expected_endpoints).perform_tests
