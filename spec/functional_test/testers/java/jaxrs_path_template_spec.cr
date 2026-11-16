require "../../func_spec.cr"

# #3278: a method-level `@Path("/")` (or any trailing `/`) adds no segment.
# #3298: `{client-uuid}` / `{role.name}` are real path params.
# `{path: .+}` takes the rest of the path; any other regex stays one segment.
expected_endpoints = [
  Endpoint.new("/items", "GET"),
  Endpoint.new("/items", "POST"),
  Endpoint.new("/items/archived", "GET"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/clients/{client-uuid}/roles/{role.name}", "GET", [
    Param.new("client-uuid", "", "path"),
    Param.new("role.name", "", "path"),
  ]),
  Endpoint.new("/clients/{clientId}/scopes", "GET", [
    Param.new("clientId", "", "path"),
  ]),
  Endpoint.new("/files/{*path}", "GET", [Param.new("path", "", "path")]),
  Endpoint.new("/files/by-id/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/java/jaxrs_path_template/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
