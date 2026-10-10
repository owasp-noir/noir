require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/:id", "GET", [
    Param.new("id", "", "path"),
    Param.new("fields", "", "query"),
  ]),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/admin/users/:id", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/admin/v2/settings", "PUT", [Param.new("mode", "", "query")]),
  Endpoint.new("/admin/raw", "GET"),
  Endpoint.new("/files/:*", "GET", [Param.new("*", "", "path")]),
  Endpoint.new("/ping", "ANY"),
  Endpoint.new("/secured", "GET", [Param.new("token", "", "query")]),
  Endpoint.new("/audited", "POST"),
  Endpoint.new("/me/profile", "GET"),
]

FunctionalTester.new("fixtures/scala/finatra/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
