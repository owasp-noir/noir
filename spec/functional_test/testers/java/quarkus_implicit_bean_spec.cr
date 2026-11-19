require "../../func_spec.cr"

# Quarkus REST treats a parameter whose class has annotated fields as a
# bean parameter with or without `@BeanParam`; a plain DTO stays the body.
bean = [
  Param.new("filter", "", "query"),
  Param.new("X-Bean-H", "", "header"),
  Param.new("page_no", "", "query"),
]

expected_endpoints = [
  Endpoint.new("/search/implicit", "GET", bean),
  Endpoint.new("/search/explicit", "GET", bean),
  Endpoint.new("/search/items", "POST", [Param.new("name", "", "json")]),
]

FunctionalTester.new("fixtures/java/quarkus_implicit_bean/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
