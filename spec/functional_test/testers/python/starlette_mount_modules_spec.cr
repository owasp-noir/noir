require "../../func_spec.cr"

# `Mount('/x', routes=users.routes)`, `routes=<imported list>` and
# `app=<imported app>` serve the other module's routes under the mount path.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/w01-users/", "GET"),
  Endpoint.new("/w01-users/", "POST"),
  Endpoint.new("/w01-users/{username}", "GET", [Param.new("username", "", "path")]),
  Endpoint.new("/w02-auth/login", "POST"),
  Endpoint.new("/w03-billing/invoices", "GET"),
  Endpoint.new("/w04-billing-app/pay", "POST"),
]

FunctionalTester.new("fixtures/python/starlette_mount_modules/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
