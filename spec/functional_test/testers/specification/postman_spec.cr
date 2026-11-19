require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET", [
    Param.new("Authorization", "Bearer token123", "header"),
    Param.new("page", "1", "query"),
    Param.new("limit", "10", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("name", "John Doe", "json"),
    Param.new("email", "john@example.com", "json"),
  ]),
  Endpoint.new("/users/:userId", "PUT", [
    Param.new("userId", "123", "path"),
    Param.new("name", "Jane Doe", "form"),
    Param.new("email", "jane@example.com", "form"),
  ]),
]

FunctionalTester.new("fixtures/specification/postman/common/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

FunctionalTester.new("fixtures/specification/postman/folders/", {
  :techs     => 1,
  :endpoints => 2,
}, nil).perform_tests

FunctionalTester.new("fixtures/specification/postman/v2_0/", {
  :techs     => 1,
  :endpoints => 1,
}, nil).perform_tests

# Postman API export shape: the collection sits under a top-level `collection` key.
FunctionalTester.new("fixtures/specification/postman/wrapped/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/identity/api/auth/signup", "POST", [
    Param.new("email", "{{email}}", "json"),
  ]),
  Endpoint.new("/workshop/api/shop/orders/42", "GET"),
]).perform_tests

# Nested JSON body and GraphQL variable values are emitted as JSON text.
FunctionalTester.new("fixtures/specification/postman/nested_body/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/orders", "POST", [
    Param.new("customer", %({"id":7,"email":"a@b.c"}), "json"),
    Param.new("items", %([{"sku":"x1","qty":2}]), "json"),
    Param.new("note", "plain", "json"),
    Param.new("sent_at", "", "json"),
  ]),
  Endpoint.new("/graphql", "POST", [
    Param.new("filter", %({"status":"open"}), "json"),
    Param.new("first", "10", "json"),
  ]),
]).perform_tests
