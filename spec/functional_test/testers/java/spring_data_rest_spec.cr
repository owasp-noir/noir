require "../../func_spec.cr"

page_params = [Param.new("page", "", "query"), Param.new("size", "", "query"), Param.new("sort", "", "query")]
person_body = [Param.new("firstName", "", "json"), Param.new("lastName", "", "json")]
order_body = [Param.new("status", "", "json")]
company_body = [Param.new("name", "", "json")]
item_body = [Param.new("sku", "", "json")]

expected_endpoints = [
  # @RepositoryRestResource(path = "people"), Paging + Crud.
  Endpoint.new("/people", "GET", page_params),
  Endpoint.new("/people", "POST", person_body),
  Endpoint.new("/people/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/people/{id}", "PUT", person_body),
  Endpoint.new("/people/{id}", "PATCH", person_body),
  Endpoint.new("/people/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/people/search", "GET"),
  Endpoint.new("/people/search/findByLastName", "GET", [Param.new("name", "", "query")]),
  # Unannotated: pluralized entity path; deleteById exported = false drops DELETE.
  Endpoint.new("/orders", "GET", page_params),
  Endpoint.new("/orders", "POST", order_body),
  Endpoint.new("/orders/{id}", "GET"),
  Endpoint.new("/orders/{id}", "PUT", order_body),
  Endpoint.new("/orders/{id}", "PATCH", order_body),
  Endpoint.new("/orders/search", "GET"),
  Endpoint.new("/orders/search/byStatus", "GET", [Param.new("status", "", "query")] + page_params),
  # Read-only Repository: only declared finders.
  Endpoint.new("/categories", "GET", page_params),
  Endpoint.new("/categories/{id}", "GET"),
  Endpoint.new("/categories/search", "GET"),
  Endpoint.new("/categories/search/countByName", "GET", [Param.new("name", "", "query")]),
  # Through a @NoRepositoryBean base repository.
  Endpoint.new("/companies", "GET", page_params),
  Endpoint.new("/companies", "POST", company_body),
  Endpoint.new("/companies/{id}", "GET"),
  Endpoint.new("/companies/{id}", "PUT", company_body),
  Endpoint.new("/companies/{id}", "PATCH", company_body),
  Endpoint.new("/companies/{id}", "DELETE"),
  # inventory module: spring.data.rest.base-path = /api.
  Endpoint.new("/api/items", "GET", page_params),
  Endpoint.new("/api/items", "POST", item_body),
  Endpoint.new("/api/items/{id}", "GET"),
  Endpoint.new("/api/items/{id}", "PUT", item_body),
  Endpoint.new("/api/items/{id}", "PATCH", item_body),
  Endpoint.new("/api/items/{id}", "DELETE"),
]

# java_spring + java_spring_data_rest. SecretRepository (exported = false),
# the package-private AuditRepository and the plain-JPA legacy module's
# WidgetRepository export nothing.
FunctionalTester.new("fixtures/java/spring_data_rest/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
