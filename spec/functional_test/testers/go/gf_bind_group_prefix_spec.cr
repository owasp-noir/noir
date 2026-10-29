require "../../func_spec.cr"

# GoFrame standard routing: a `g.Meta` route is mounted under the group
# that `Bind`s its controller (`group.Bind(controller.NewCtrl())` inside
# `s.Group("/api", ...)`); a request type no bound controller takes keeps
# its tag path. `BindHandler` and `group.ALL` answer every method.
expected_endpoints = [
  Endpoint.new("/api/profile", "GET"),
  Endpoint.new("/unbound", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/hook", "GET"),
  Endpoint.new("/hook", "POST"),
  Endpoint.new("/hook", "PUT"),
  Endpoint.new("/hook", "PATCH"),
  Endpoint.new("/hook", "DELETE"),
  Endpoint.new("/hook", "HEAD"),
  Endpoint.new("/hook", "OPTIONS"),
  Endpoint.new("/api/any", "GET"),
  Endpoint.new("/api/any", "POST"),
  Endpoint.new("/api/any", "PUT"),
  Endpoint.new("/api/any", "PATCH"),
  Endpoint.new("/api/any", "DELETE"),
  Endpoint.new("/api/any", "HEAD"),
  Endpoint.new("/api/any", "OPTIONS"),
]

FunctionalTester.new("fixtures/go/gf_bind_group_prefix/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
