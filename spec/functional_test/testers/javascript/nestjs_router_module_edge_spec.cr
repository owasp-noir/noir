require "../../func_spec.cr"

# A controller listed by a mounted and an unmounted module is served at both
# paths; the module path goes after the URI version; a router path that
# starts with the global prefix still gets it; `RouterModule.register` inside
# a string mounts nothing.
expected_endpoints = [
  Endpoint.new("/api/v1/admin/users", "GET"),
  Endpoint.new("/api/admin/shared", "GET"),
  Endpoint.new("/api/shared", "GET"),
  Endpoint.new("/api/str", "GET"),
  Endpoint.new("/api/api/zoo/z", "GET"),
]

FunctionalTester.new("fixtures/javascript/nestjs_router_module_edge/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

# Module names are resolved through the routes file's own import: apps/b's
# UsersModule is not the one apps/a mounts under `a`.
monorepo_endpoints = [
  Endpoint.new("/a/users", "GET"),
  Endpoint.new("/users", "GET"),
]

FunctionalTester.new("fixtures/javascript/nestjs_router_module_monorepo/", {
  :techs     => 1,
  :endpoints => monorepo_endpoints.size,
}, monorepo_endpoints).perform_tests
