require "../../func_spec.cr"

# Kratos `Router.Group` joins its prefix onto the parent router's
# (`srv.Route("/api")` -> `r.Group("/v2")` -> `r2.Group("/admin")`).
expected_endpoints = [
  Endpoint.new("/api/hello/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/api/v2/say/{name}", "GET", [Param.new("name", "", "path")]),
  Endpoint.new("/api/v2/admin/reset", "POST"),
  Endpoint.new("/api/v2/admin/settings", "PUT", [Param.new("body", "", "json")]),
  Endpoint.new("/api/v2/admin/settings", "PATCH", [Param.new("body", "", "json")]),
]

FunctionalTester.new("fixtures/go/kratos_router_group/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
