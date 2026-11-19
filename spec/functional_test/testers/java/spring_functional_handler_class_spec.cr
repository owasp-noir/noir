require "../../func_spec.cr"

# `route().GET("/person", handler::listPeople)` with the handler in its own
# `PersonHandler` class reports what that method reads off `ServerRequest`.
expected_endpoints = [
  Endpoint.new("/person/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/person", "GET", [Param.new("name", "", "query"), Param.new("X-Tenant", "", "header")]),
  Endpoint.new("/person", "POST", [Param.new("name", "", "json"), Param.new("age", "", "json")]),
  Endpoint.new("/local", "GET", [Param.new("name", "", "query"), Param.new("X-Tenant", "", "header")]),
]

FunctionalTester.new("fixtures/java/spring_functional_handler_class/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
