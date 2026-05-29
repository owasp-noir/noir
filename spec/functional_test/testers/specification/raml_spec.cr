require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/{userId}", "GET", [
    Param.new("userId", "", "path"),
    Param.new("userId", "", "query"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

nested_endpoints = [
  Endpoint.new("/v1/pets", "GET", [
    Param.new("filter", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/v1/pets", "POST", [
    Param.new("name", "", "json"),
    Param.new("breed", "", "json"),
  ]),
  Endpoint.new("/v1/pets/{petId}", "GET", [
    Param.new("petId", "", "path"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/v1/pets/{petId}/avatar", "POST", [
    Param.new("petId", "", "path"),
    Param.new("file", "", "form"),
    Param.new("caption", "", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml_nested/", {
  :techs     => 1,
  :endpoints => nested_endpoints.size,
}, nested_endpoints).perform_tests

advanced_endpoints = [
  Endpoint.new("/api/{version}/users", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("page", "", "query"),
    Param.new("per_page", "", "query"),
    Param.new("version", "", "path"),
  ]),
  Endpoint.new("/api/{version}/users", "POST", [
    Param.new("Authorization", "", "header"),
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
    Param.new("version", "", "path"),
  ]),
  Endpoint.new("/api/{version}/users/{userId}", "GET", [
    Param.new("Authorization", "", "header"),
    Param.new("version", "", "path"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/api/{version}/users/{userId}", "PUT", [
    Param.new("Authorization", "", "header"),
    Param.new("name", "", "json"),
    Param.new("status", "", "json"),
    Param.new("version", "", "path"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/api/{version}/users/{userId}", "DELETE", [
    Param.new("Authorization", "", "header"),
    Param.new("version", "", "path"),
    Param.new("userId", "", "path"),
  ]),
  Endpoint.new("/api/{version}/users/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("version", "", "path"),
  ]),
  Endpoint.new("/api/{version}/reports", "GET", [
    Param.new("from", "", "query"),
    Param.new("to", "", "query"),
    Param.new("version", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/specification/raml_advanced/", {
  :techs     => 1,
  :endpoints => advanced_endpoints.size,
}, advanced_endpoints).perform_tests
