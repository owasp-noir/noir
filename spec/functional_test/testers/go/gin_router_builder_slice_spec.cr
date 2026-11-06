require "../../func_spec.cr"

# go-admin registers each module's builder by appending it to a slice in
# `init()` (`routerCheckRole = append(routerCheckRole, registerX)`); a loop
# hands every appended builder the versioned group
# (`for _, f := range routerCheckRole { f(v, auth) }`).
expected_endpoints = [
  Endpoint.new("/api/v1/product", "GET"),
  Endpoint.new("/api/v1/product", "POST"),
  Endpoint.new("/api/v1/captcha", "GET"),
  Endpoint.new("/orphan", "GET"),
  # shadow.go: only a package-level slice's appends count
  Endpoint.new("/v2/sa", "GET"),
  Endpoint.new("/sb", "GET"),
  Endpoint.new("/local", "GET"),
]

FunctionalTester.new("fixtures/go/gin_router_builder_slice/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
