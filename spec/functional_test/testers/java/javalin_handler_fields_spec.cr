require "../../func_spec.cr"

# A handler passed as a `Handler` field (`UserController.fetchById`) or a
# factory call (`users.create()`) after a `/` path, in Java and Kotlin, and
# Kotlin's path-less `get(KtUsers.list)` inside `path()`. Map calls with a
# value expression (`settings.put("key", x)`) stay out.
expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/control-lambda", "GET"),
  Endpoint.new("/control-ref/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/kt-api/users", "GET"),
  Endpoint.new("/kt-field", "GET"),
]

FunctionalTester.new("fixtures/java/javalin_handler_fields/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
