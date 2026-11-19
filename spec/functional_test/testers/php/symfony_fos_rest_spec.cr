require "../../func_spec.cr"

# FOSRestBundle routes written through an aliased or imported namespace
# (`#[Rest\Route]`, `#[Rest\Get]`, `@Rest\Put`, an imported `Delete`); the
# verb class fixes the method. A `Post` that is not imported from FOSRest
# and API Platform's `Get` are not routes.
expected_endpoints = [
  Endpoint.new("/control", "GET"),
  Endpoint.new("/api/aliased-route", "GET"),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users", "POST", [Param.new("email", "", "form")]),
  Endpoint.new("/api/users/{id}", "PUT", [Param.new("id", "", "path"), Param.new("notify", "", "query")]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/php/symfony_fos_rest/", {
  :techs     => 3,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
