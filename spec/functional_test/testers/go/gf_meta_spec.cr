require "../../func_spec.cr"

# GoFrame standardized routing (#gf-meta). Request structs embed
# `g.Meta` with `path:`/`method:` tags that fully define the route;
# `group.Bind(controller)` wires them up. The tag is the route, exactly
# as gf's own OpenAPI generator reads it, so the analyzer surfaces it
# directly from the struct definition.
#
# The controller fixture also parks three value-getter `.Get(...)` calls
# (`genv.Get`, `r.Get`) and a `group.Bind(...)` — none are endpoints, so
# this spec doubles as a regression test that they don't mint phantom
# routes.
expected_endpoints = [
  Endpoint.new("/user/get", "GET", [
    Param.new("id", "", "query"),
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/user/create", "POST", [
    Param.new("username", "", "json"),
    Param.new("email", "", "json"),
  ]),
  # Multi-verb `method:"put,patch"` fans out to one endpoint per verb.
  Endpoint.new("/user/update", "PUT", [
    Param.new("id", "", "json"),
  ]),
  Endpoint.new("/user/update", "PATCH", [
    Param.new("id", "", "json"),
  ]),
  # Method-less meta tag responds to ALL methods -> fans out to the
  # seven canonical HTTP verbs (so the optimizer doesn't drop a bare
  # "ALL" verb).
  Endpoint.new("/user/list", "GET"),
  Endpoint.new("/user/list", "POST"),
  Endpoint.new("/user/list", "PUT"),
  Endpoint.new("/user/list", "PATCH"),
  Endpoint.new("/user/list", "DELETE"),
  Endpoint.new("/user/list", "HEAD"),
  Endpoint.new("/user/list", "OPTIONS"),
]

FunctionalTester.new("fixtures/go/gf_meta/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
