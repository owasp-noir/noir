require "../../func_spec.cr"

# #3271: a sub-resource class in another file resolves its `@BeanParam` and
# body DTO types through its own imports, not the parent resource's.
expected_endpoints = [
  Endpoint.new("/users/{userId}/items", "GET", [
    Param.new("userId", "", "path"),
    Param.new("page", "", "query"),
    Param.new("X-Tenant", "", "header"),
  ]),
  Endpoint.new("/users/{userId}/items", "POST", [
    Param.new("userId", "", "path"),
    Param.new("name", "", "json"),
    Param.new("price", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/java/jaxrs_subresource_scope/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
