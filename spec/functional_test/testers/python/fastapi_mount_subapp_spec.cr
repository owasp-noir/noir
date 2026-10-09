require "../../func_spec.cr"

# A sub-application mounted with `app.mount(prefix, sub)` serves its routes
# (and its included routers' routes) under the mount path only.
expected_endpoints = [
  Endpoint.new("/app", "GET"),
  Endpoint.new("/subapi/sub", "GET"),
  Endpoint.new("/admin/users/{user_id}", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/static/*", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_mount_subapp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
