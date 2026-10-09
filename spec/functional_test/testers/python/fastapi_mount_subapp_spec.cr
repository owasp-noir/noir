require "../../func_spec.cr"

# A sub-application mounted with `app.mount(prefix, sub)` serves its routes
# (and its included routers' routes) under the mount path only. A
# route-less wrapper in another file (`devwrap.py`) that mounts the real
# app adds the prefixed copies without hiding the app's own root routes.
expected_endpoints = [
  Endpoint.new("/app", "GET"),
  Endpoint.new("/subapi/sub", "GET"),
  Endpoint.new("/admin/users/{user_id}", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/static/*", "GET"),
  Endpoint.new("/prefixed/app", "GET"),
  Endpoint.new("/prefixed/subapi/sub", "GET"),
  Endpoint.new("/prefixed/admin/users/{user_id}", "GET", [Param.new("user_id", "", "path")]),
  Endpoint.new("/prefixed/static/*", "GET"),
]

FunctionalTester.new("fixtures/python/fastapi_mount_subapp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
