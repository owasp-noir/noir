require "../../func_spec.cr"

# `Router("/users" -> UserEndpoints.endpoints(svc), "/pets" -> petRoutes.routes)`
# mounts routes declared in another file under their prefixes.
expected_endpoints = [
  Endpoint.new("/internal/ping", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/pets", "POST"),
  Endpoint.new("/pets/{name}", "DELETE", [Param.new("name", "", "path")]),
]

FunctionalTester.new("fixtures/scala/http4s_mounts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
