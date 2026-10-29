require "../../func_spec.cr"

# Kratos `Router.Group` joins its prefix onto the parent router's
# (`srv.Route("/api")` -> `r.Group("/v2")` -> `r2.Group("/admin")`).
expected_endpoints = [
  Endpoint.new("/api/hello/{name}", "GET"),
  Endpoint.new("/api/v2/say/{name}", "GET"),
  Endpoint.new("/api/v2/admin/reset", "POST"),
]

FunctionalTester.new("fixtures/go/kratos_router_group/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
