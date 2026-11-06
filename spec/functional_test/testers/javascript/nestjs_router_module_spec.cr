require "../../func_spec.cr"

# `RouterModule.register` mounts a module's controllers under its path:
# a constant imported from another file, a plain string, `children`
# nesting, and a module that is not registered (its controller keeps its own
# path). A commented-out route entry mounts nothing.
expected_endpoints = [
  Endpoint.new("/api/v2/me", "GET"),
  Endpoint.new("/api/private/me", "GET"),
  Endpoint.new("/api/private/me/profile", "POST"),
  Endpoint.new("/api/private/inner", "GET"),
  Endpoint.new("/other", "GET"),
]

FunctionalTester.new("fixtures/javascript/nestjs_router_module/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
